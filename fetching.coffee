# FIXME: EJSON.stringify doesn't canonically order the keys
# so {a: 5, b: 6} and {b: 6, a: 5} look like different
# querySpecs. More generally, we need a querySpec consolidation.


J.fetching =
    SESSION_ID: "#{parseInt Math.random() * 1000}"

    _requestInProgress: false

    # Latest client-side state and whether it's changed since we
    # last called the server's update method
    _requestersByQs: {} # querySpecString: {computationId: computation}
    _requestsChanged: false

    # Snapshot of what the cursors will be after the next _updateDataQueries returns
    _nextUnmergedQsSet: {} # querySpecString: true
    _nextMergedQsSet: {}

    # Snapshot of what we last successfully asked the server for
    _unmergedQsSet: {} # mergedQuerySpecString: true
    _mergedQsSet: {} # mergedQuerySpecString: true


    _getIdsForSimpleIdQs: (qs) ->
        if _.isString(qs.selector) and not qs.fields?
            [qs.selector]
        else if _.size(qs.selector) is 1 and qs.selector._id? and not qs.fields?
            if _.isString qs.selector._id
                [qs.selector._id]
            else if _.isObject(qs.selector._id) and _.size(qs.selector._id) is 1 and
            qs.selector._id.$in? and not qs.fields? and not qs.skip? and not qs.limit?
                qs.selector._id.$in


    isQueryReady: (querySpec) ->
        querySpecString = EJSON.stringify querySpec
        simpleIds = @_getIdsForSimpleIdQs querySpec

        _isQueryReady = (readyQsSet) =>
            return querySpecString of readyQsSet if not simpleIds?

            for readyQsString of readyQsSet
                readyQs = EJSON.parse readyQsString
                continue if readyQs.modelName isnt querySpec.modelName

                readySimpleIds = @_getIdsForSimpleIdQs readyQs
                continue if not readySimpleIds?

                return true if _.all(id in readySimpleIds for id in simpleIds)

            false

        _isQueryReady(@_mergedQsSet) and _isQueryReady(@_nextMergedQsSet)


    getMerged: (querySpecs) ->
        requestedIdsByModel = {} # modelName: {id: true}

        mergedQuerySpecs = []

        for qs in querySpecs
            simpleIds = @_getIdsForSimpleIdQs qs
            if simpleIds?.length
                # We'll add a merged version of it later
                requestedIdsByModel[qs.modelName] ?= {}
                for id in simpleIds
                    requestedIdsByModel[qs.modelName][id] = true
            else
                mergedQuerySpecs.push qs

        _.forEach requestedIdsByModel, (requestedIdSet, modelName) ->
            return if _.isEmpty requestedIdSet
            mergedQuerySpecs.push
                modelName: modelName
                selector: _id: $in: _.keys(requestedIdSet).sort()

        mergedQuerySpecs


    remergeQueries: ->
        return if @_requestInProgress or not @_requestsChanged
        @_requestsChanged = false

        newUnmergedQsStrings = _.keys @_requestersByQs
        newUnmergedQuerySpecs = (EJSON.parse qsString for qsString in newUnmergedQsStrings)
        @_nextUnmergedQsSet = {}
        @_nextUnmergedQsSet[qsString] = true for qsString in newUnmergedQsStrings
        unmergedQsStringsDiff = J.util.diffStrings _.keys(@_unmergedQsSet), _.keys(@_nextUnmergedQsSet)

        newMergedQuerySpecs = @getMerged newUnmergedQuerySpecs
        newMergedQsStrings = (EJSON.stringify querySpec for querySpec in newMergedQuerySpecs)
        @_nextMergedQsSet = {}
        @_nextMergedQsSet[qsString] = true for qsString in newMergedQsStrings
        mergedQsStringsDiff = J.util.diffStrings _.keys(@_mergedQsSet), _.keys(@_nextMergedQsSet)

        addedQuerySpecs = (EJSON.parse qsString for qsString in mergedQsStringsDiff.added)
        deletedQuerySpecs = (EJSON.parse qsString for qsString in mergedQsStringsDiff.deleted)

        return unless addedQuerySpecs.length or deletedQuerySpecs.length

        debug = true
        if debug
            consolify = (querySpec) ->
                obj = _.clone querySpec
                for x in ['selector', 'fields', 'sort']
                    if x of obj then obj[x] = J.util.stringify obj[x]
                obj

            if addedQuerySpecs.length
                console.groupCollapsed("+")
                for qsString in unmergedQsStringsDiff.added
                    for computationId, computation of @_requestersByQs[qsString]
                        if computation.autoVar?
                            console.log computation.autoVar
                        else
                            console.log computation
                console.groupEnd()
                console.debug "    ", consolify(qs) for qs in addedQuerySpecs
            if deletedQuerySpecs.length
                console.debug "-"
                console.debug "    ", consolify(qs) for qs in deletedQuerySpecs

        @_requestInProgress = true
        Meteor.call '_updateDataQueries',
            @SESSION_ID,
            addedQuerySpecs,
            deletedQuerySpecs,
            (error, result) =>
                @_requestInProgress = false
                if error
                    console.error "Fetching error:", error
                    return

                @_unmergedQsSet = _.clone @_nextUnmergedQsSet
                @_mergedQsSet = _.clone @_nextMergedQsSet

                for addedUnmergedQsString in unmergedQsStringsDiff.added
                    for computationId in _.keys @_requestersByQs[addedUnmergedQsString] ? {}
                        @_requestersByQs[addedUnmergedQsString][computationId].invalidate()

                # There may be changes to @_requestersByQs that we couldn't act on
                # until this request was done.
                Tracker.afterFlush (=> @remergeQueries()), Math.POSITIVE_INFINITY


    _deleteComputationQsRequests: (computation) ->
        for qsString of @_requestersByQs
            delete @_requestersByQs[qsString][computation._id]
            if _.isEmpty @_requestersByQs[qsString]
                delete @_requestersByQs[qsString]
            @_requestsChanged = true
            Tracker.afterFlush (=> @remergeQueries()), Math.POSITIVE_INFINITY


    requestQuery: (querySpec) ->
        qsString = EJSON.stringify querySpec

        if Tracker.active
            # We may not need reactivity per se, since the query should
            # never stop once it's started. But we still want to track
            # which computations need this querySpec.
            computation = Tracker.currentComputation
            # console.log computation.tag, 'requests a query', querySpec.modelName,
            #     querySpec.selector, @isQueryReady querySpec
            @_requestersByQs[qsString] ?= {}
            if computation._id not of @_requestersByQs[qsString]
                @_requestersByQs[qsString][computation._id] = computation

                if computation.component?
                    # Components are slow to re-render relative to the flush cycle, so don't
                    # kill its fetches yet, or those of its reactives.
                else computation.onInvalidate =>
                    # console.log computation.tag, 'cancels a query', computation.stopped,
                    #     querySpec.modelName, querySpec.selector, @isQueryReady querySpec
                    @_deleteComputationQsRequests computation


        if @isQueryReady querySpec
            modelClass = J.models[querySpec.modelName]
            options = {}
            for optionName in ['fields', 'sort', 'skip', 'limit']
                if querySpec[optionName]? then options[optionName] = querySpec[optionName]
            return J.List modelClass.find(querySpec.selector, options).fetch()

        if Tracker.active
            @_requestsChanged = true
            Tracker.afterFlush (=> @remergeQueries()), Math.POSITIVE_INFINITY
            throw J.makeValueNotReadyObject()
        else
            undefined
###
    Copyright 2015, Quixey Inc.
    All rights reserved.

    Licensed under the Modified BSD License found in the
    LICENSE file in the root directory of this source tree.
###

J.fetching =
    SESSION_ID: "#{parseInt Math.random() * 1000000}"

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


    checkQuerySpec: (querySpec) ->
        ###
            Throws an error if the querySpec is invalid
        ###

        if querySpec.fields?
            if J.util.isPlainObject(querySpec.selector) then for sKey, sValue of querySpec.selector
                if sKey isnt '_id' and sKey[0] isnt '$'
                    ok = false
                    for fKey, fValue of querySpec.fields
                        if fKey.split('.')[0] is sKey
                            ok = true
                            break
                    if not ok
                        throw new Error "
                            Missing projection for selector key #{JSON.stringify sKey}.
                            When fetching with a projection, the projection must
                            include/exclude every key in the selector so that
                            the fetch also works as expected on the client."

            if querySpec.sort? then for sKey, sValue of querySpec.sort
                if sKey isnt '_id' and sKey[0] isnt '$'
                    ok = false
                    for fKey, fValue of querySpec.fields
                        if fKey.split('.')[0] is sKey
                            ok = true
                            break
                    if not ok
                        throw new Error "
                            Missing projection for sort key #{JSON.stringify sKey}.
                            When fetching with a projection, the projection must
                            include/exclude every key in the sort so that
                            the fetch also works as expected on the client."


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
        # FIXME: EJSON.stringify doesn't canonically order the keys
        # so {a: 5, b: 6} and {b: 6, a: 5} may look like different
        # querySpecs.
        # TODO: The client can make more inferences about which
        # of its requested data is already available for use.
        # For example, the client should realize that any query
        # for an _id can be satisfied synchronously if that _id
        # is present in the local collection, even as the result
        # of previously watching a non-id-based query.

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

            if deletedQuerySpecs.length
                console.groupCollapsed "-"
                console.debug "    ", consolify(qs) for qs in deletedQuerySpecs
                console.groupEnd()
            if addedQuerySpecs.length
                console.groupCollapsed "+"
                for qsString in unmergedQsStringsDiff.added
                    for computationId, computation of @_requestersByQs[qsString]
                        if false then console.log computation
                console.debug "    ", consolify(qs) for qs in addedQuerySpecs
                console.groupEnd()

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
                Tracker.afterFlush (=> @remergeQueries()), Number.POSITIVE_INFINITY


    _deleteComputationQsRequests: (computation) ->
        return if not computation._requestingData
        for qsString in _.keys @_requestersByQs
            delete @_requestersByQs[qsString][computation._id]
            if _.isEmpty @_requestersByQs[qsString]
                delete @_requestersByQs[qsString]
        computation._requestingData = false
        @_requestsChanged = true
        Tracker.afterFlush (=> @remergeQueries()), Number.POSITIVE_INFINITY


    requestQuery: (querySpec) ->
        J.assert Tracker.active

        @checkQuerySpec querySpec

        qsString = EJSON.stringify querySpec
        computation = Tracker.currentComputation

        # We may not need reactivity per se, since the query should
        # never stop once it's started. But we still want to track
        # which computations need this querySpec.
        # console.log computation.tag, 'requests a query', querySpec.modelName,
        #     querySpec.selector, @isQueryReady querySpec
        @_requestersByQs[qsString] ?= {}
        if computation._id not of @_requestersByQs[qsString]
            @_requestersByQs[qsString][computation._id] = computation
            computation._requestingData = true
            # Note: AutoVar handles logic to remove from @_requestersByQueue
            # because it involves complicated sequencing with React component
            # rendering.

        if @isQueryReady querySpec
            modelClass = J.models[querySpec.modelName]
            options = {}
            for optionName in ['fields', 'sort', 'skip', 'limit']
                if querySpec[optionName]? then options[optionName] = querySpec[optionName]

            if Tracker.active
                results = J.List Tracker.nonreactive ->
                    modelClass.find(querySpec.selector, options).fetch()

                # The individual model instances' getters have their own reactivity, so
                # this query should only invalidate if a result gets added/removed/moved.
                idQueryOptions = _.clone options
                idQueryOptions.fields = _id: 1
                idQueryOptions.transform = null

                initializing = true
                invalidator = -> computation.invalidate() if not initializing
                modelClass.find(querySpec.selector, idQueryOptions).observe
                    added: invalidator
                    movedTo: invalidator
                    removed: invalidator
                initializing = false

                results

            else
                J.List modelClass.find(querySpec.selector, options).fetch()

        else
            @_requestsChanged = true
            Tracker.afterFlush (=> @remergeQueries()), Number.POSITIVE_INFINITY
            throw J.makeValueNotReadyObject()
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


    _deleteComputationQsRequests: (computation) ->
        return if not computation._requestingData
        for qsString in _.keys @_requestersByQs
            delete @_requestersByQs[qsString][computation._id]
            if _.isEmpty @_requestersByQs[qsString]
                delete @_requestersByQs[qsString]
        computation._requestingData = false
        @_requestsChanged = true
        Tracker.afterFlush (=> @remergeQueries()), Number.POSITIVE_INFINITY


    _qsToFindOptions: (qs) ->
        options = {}
        for optionName in ['fields', 'sort', 'skip', 'limit']
            if qs[optionName]? then options[optionName] = J.util.deepClone qs[optionName]
        options


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


    getMerged: (querySpecs) ->
        # FIXME: EJSON.stringify doesn't canonically order the keys
        # so {a: 5, b: 6} and {b: 6, a: 5} may look like different
        # querySpecs.

        ###
            1.
                Merge all the querySpecs that select on _id using
                projectionByModelInstance.
            2.
                Attempt to pairwise merge all the querySpecs that
                don't select on _id.
        ###

        projectionByModelInstance = {} # modelName: id: fieldSpec: 1
        nonIdQuerySpecsByModel = {} # modelName: [querySpecs] (will be pairwise merged)
        mergedQuerySpecs = []

        _getSelectorIds = (qs) =>
            qs = J.util.deepClone qs
            if _.isString(qs.selector)
                qs.selector = _id: qs.selector

            if qs.selector._id?
                # Note that if the selector has keys other than "_id" that may drop
                # the result count from 1 to 0, we'll just ignore that and send a
                # dumber merged query to the server.

                if _.isString qs.selector._id
                    [qs.selector._id]
                else if (
                    _.isObject(qs.selector._id) and _.size(qs.selector._id) is 1 and
                    qs.selector._id.$in? and not qs.limit? and not qs.skip
                )
                    qs.selector._id.$in


        for qs in querySpecs
            selectorIds = _getSelectorIds qs
            if selectorIds?.length
                # (1) Merge this QS into projectionByModelInstance

                for selectorId in selectorIds
                    if _.size qs.fields
                        for fieldSpec, include of qs.fields
                            existingInclude = J.util.getField(
                                projectionByModelInstance
                                [qs.modelName, '?.', selectorId, '?.', fieldSpec]
                            )
                            J.util.setField(
                                projectionByModelInstance
                                [qs.modelName, selectorId, fieldSpec]
                                if include or existingInclude then 1 else 0
                                true
                            )
                    else
                        J.util.setField(
                            projectionByModelInstance
                            [qs.modelName, selectorId]
                            {}
                            true
                        )

            else
                # (2) Add this to the list of non-ID-selecting querySpecs
                # to be pairwise merged.

                nonIdQuerySpecsByModel[qs.modelName] ?= []
                nonIdQuerySpecsByModel[qs.modelName].push qs


        # (1) Dump projectionByModelInstance into mergedQuerySpecs
        for modelName, projectionById of projectionByModelInstance
            idsByProjectionString = {} # projectionString: [instanceIds]
            for instanceId, projection of projectionById
                projectionString = JSON.stringify projection
                idsByProjectionString[projectionString] ?= []
                idsByProjectionString[projectionString].push instanceId

            for projectionString, instanceIds of idsByProjectionString
                projection = JSON.parse projectionString
                mergedQuerySpecs.push
                    modelName: modelName
                    selector: _id: $in: instanceIds
                    fields: projection


        # (2) Pairwise merge the nonIdQuerySpecs
        for modelName, nonIdQuerySpecs of nonIdQuerySpecsByModel
            qsStringSet = {} # qsString: true
            for qs in nonIdQuerySpecs
                qsStringSet[EJSON.stringify qs] = true

            # Iterate until no pair of qsStrings in qsStringSet
            # can be pairwise merged.
            while true
                mergedSomething = false

                qsStrings = _.keys qsStringSet
                for qsString, i in qsStrings[qsStrings.length - 1]
                    for qss in qsStrings[i + 1...]
                        pairwiseMergedQsString = @tryQsPairwiseMerge qsString, qss
                        if pairwiseMergedQsString?
                            delete qsStringSet[qsString]
                            delete qsStringSet[qss]
                            qsStringSet[pairwiseMergedQsString] = true
                            mergedSomething = true
                            break

                    break if mergedSomething

                break if not mergedSomething

            # Dump qsStringSet into mergedQuerySpecs
            for qsString of qsStringSet
                mergedQuerySpecs.push EJSON.parse qsString


        mergedQuerySpecs


    isQueryReady: (qs) ->
        qsString = EJSON.stringify qs
        modelClass = J.models[qs.modelName]

        qs = J.util.deepClone qs
        if not J.util.isPlainObject qs.selector
            # Note that this makes qs inconsistent with qsString
            qs.selector = _id: qs.selector

        helper = =>
            return true if qsString of @_unmergedQsSet and qsString of @_nextUnmergedQsSet

            if _.isString(qs.selector._id) and qs.selector._id of modelClass.collection._attachedInstances
                # For queries with an _id filter, say it's ready as long as minimongo
                # has an attached entry with that _id and no other parts of the selector
                # rule out the one possible match.
                options = @_qsToFindOptions(qs)
                options.transform = false
                options.reactive = false
                return modelClass.findOne(qs.selector, options)?

            false

        ret = helper()
        if ret is false then console.log 'isQueryReady', ret, qsString
        ret


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


    requestQuery: (querySpec) ->
        J.assert Tracker.active

        @checkQuerySpec querySpec

        qsString = EJSON.stringify querySpec
        computation = Tracker.currentComputation

        @_requestersByQs[qsString] ?= {}
        if computation._id not of @_requestersByQs[qsString]
            @_requestersByQs[qsString][computation._id] = computation
            computation._requestingData = true
            # Note: AutoVar handles logic to remove from @_requestersByQueue
            # because it involves complicated sequencing with React component
            # rendering.

        if @isQueryReady querySpec
            modelClass = J.models[querySpec.modelName]
            options = @_qsToFindOptions querySpec

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


    tryQsPairwiseMerge: (a, b) ->
        return null if a.modelName isnt b.modelName

        null
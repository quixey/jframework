# FIXME: EJSON.stringify doesn't canonically order the keys
# so {a: 5, b: 6} and {b: 6, a: 5} look like different
# querySpecs. More generally, we need a querySpec consolidation.


J.fetching =
    SESSION_ID: "#{parseInt Math.random() * 1000}"
    FETCH_IN_PROGRESS: {
        name: "J.fetching.FETCH_IN_PROGRESS"
        message: "This error is thrown to get out of AutoVar
            valueFuncs and wait for fetch operations. It will
            crash if run in a normal Tracker.autorun."
    }

    # Latest client-side state and whether it's changed since we
    # last called the server's update method
    _requestersByQs: {} # querySpecString: {computationId: true}
    _requestsChanged: false

    # New requests that the server hasn't acknowledged yet.
    # Only useful for debugging right now.
    _waitingQsSet: {} # querySpecString: true

    # Snapshot of what we last successfully asked the server for
    _unmergedQsSet: {} # mergedQuerySpecString: true
    _mergedQsSet: {} # mergedQuerySpecString: true

    _batchDep: new J.Dependency()


    isQueryReady: (querySpec) ->
        qsString = EJSON.stringify querySpec
        qsString of @_unmergedQsSet


    getMerged: (querySpecs) ->
        # TODO
        _.clone querySpecs


    remergeQueries: ->
        return if not @_requestsChanged
        @_requestsChanged = false

        newRequestedQsStrings = _.keys @_requestersByQs
        newRequestedQuerySpecs = (EJSON.parse qsString for qsString in newRequestedQsStrings)
        newMergedQuerySpecs = @getMerged newRequestedQuerySpecs
        newMergedQsStrings = (EJSON.stringify querySpec for querySpec in newMergedQuerySpecs)

        mergedQsStringDiff = J.Dict.diff _.keys(@_mergedQsSet), newMergedQsStrings
        return unless mergedQsStringDiff.added.length or mergedQsStringDiff.deleted.length

        for addedQsString in mergedQsStringDiff.added
            @_waitingQsSet[addedQsString] = true
        for deletedQsString in mergedQsStringDiff.deleted
            delete @_waitingQsSet[deletedQsString]

        addedQuerySpecs = (EJSON.parse qsString for qsString in mergedQsStringDiff.added)
        deletedQuerySpecs = (EJSON.parse qsString for qsString in mergedQsStringDiff.deleted)

        console.log '_updateDataQueries', @SESSION_ID, addedQuerySpecs, deletedQuerySpecs
        Meteor.call '_updateDataQueries',
            @SESSION_ID,
            addedQuerySpecs,
            deletedQuerySpecs,
            (error, result) =>
                if error
                    console.log "Fetching error:", error
                    return

                @_unmergedQsSet = {}
                @_unmergedQsSet[qsString] = true for qsString in newRequestedQsStrings
                @_mergedQsSet = {}
                @_mergedQsSet[qsString] = true for qsString in newMergedQsStrings

                for addedQsString in mergedQsStringDiff.added
                    delete @_waitingQsSet[qsString]

                computation = Tracker.currentComputation
                console.log "BatchDep's dependents: ", @_batchDep._dep._dependentsById
                @_batchDep.changed()


    requestQuery: (querySpec) ->
        qsString = EJSON.stringify querySpec

        if Tracker.active
            # We may not need reactivity per se, since the query should
            # never stop once it's started. But we still want to track
            # which computations need this querySpec.
            computation = Tracker.currentComputation
            @_requestersByQs[qsString] ?= {}
            @_requestersByQs[qsString][computation._id] = true
            # console.log 'computation ', computation._id, 'requests a query'
            computation.onInvalidate =>
                # console.log 'computation ', computation._id, 'cancels a query', computation.stopped
                return # FIXME
                if qsString of @_requestersByQs
                    delete @_requestersByQs[qsString][computation._id]
                    if _.isEmpty @_requestersByQs[qsString]
                        delete @_requestersByQs[qsString]
                @_requestsChanged = true
                Tracker.afterFlush =>
                    @remergeQueries()

        if @isQueryReady querySpec
            modelClass = J.models[querySpec.modelName]
            options = {}
            for optionName in ['fields', 'sort', 'skip', 'limit']
                if querySpec[optionName]? then options[optionName] = querySpec[optionName]
            return modelClass.find(querySpec.selector, options).fetch()
        else if not Tracker.active
            return undefined

        @_batchDep.depend()
        console.log "#{Tracker.currentComputation.tag} being a dependent of @_batchDep"
        Tracker.currentComputation.onInvalidate (c) =>
            console.log "INVALIDATED", c.tag

        @_requestsChanged = true
        Tracker.afterFlush =>
            @remergeQueries()

        throw @FETCH_IN_PROGRESS

f = Tracker.flush
Tracker.flush = ->
    console.log 'FLUSH'
    f()
Meteor.startup ->
    Meteor.subscribe '_jdata', J.fetching.SESSION_ID

J.fetching =
    SESSION_ID: "#{parseInt Math.random() * 1000}"
    FETCH_IN_PROGRESS: {name: "J.fetching.FETCH_IN_PROGRESS"}
    _pendingQsSet: {}
    _waitingQsSet: {}
    _readyQsSet: {} # querySpecString: true
    _batchDep: new J.Dependency()


    flushQueries: ->
        qsBatch = (EJSON.parse(qsString) for qsString of @_pendingQsSet)

        for querySpec in qsBatch
            qsString = EJSON.stringify querySpec
            @_waitingQsSet[qsString] = true

        @_pendingQsSet = {}

        Meteor.call '_addDataQueries', @SESSION_ID, qsBatch, (error, result) =>
            if error
                console.log "Fetching error:", error
                return

            for querySpec in qsBatch
                qsString = EJSON.stringify querySpec
                delete @_waitingQsSet[qsString]
                @_readyQsSet[qsString] = true

            @_batchDep.changed()


    isQueryReady: (querySpec) ->
        qsString = EJSON.stringify querySpec
        qsString of @_readyQsSet


    requestQuerySpec: (querySpec) ->
        if @isQueryReady querySpec
            console.warn "Requested a ready QuerySpec:", querySpec
            return

        qsString = EJSON.stringify querySpec
        if qsString of @_pendingQsSet or qsString of @_waitingQsSet
            return

        isNewBatch = _.isEmpty @_pendingQsSet
        @_pendingQsSet[qsString] = true
        if isNewBatch then Tracker.afterFlush =>
            @flushQueries()

        @_batchDep.depend()

        throw @FETCH_IN_PROGRESS
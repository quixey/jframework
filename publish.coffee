###
    dataSessionId: J.Dict
        querySpecSet: {qsString: true}
        mergedQuerySpecs: [
            {
                modelName:
                selector:
                fields:
                sort:
                skip:
                limit:
            }
        ]
        currentWrite: <WriteFenceWrite>?

###
dataSessions = {}


Meteor.methods
    _updateDataQueries: (dataSessionId, addedQuerySpecs, deletedQuerySpecs) ->
        log = ->
            newArgs = ["[#{dataSessionId}]"].concat _.toArray arguments
            console.log.apply console, newArgs

        log '_updateDataQueries',
            {added: addedQuerySpecs, deleted: deletedQuerySpecs}

        session = dataSessions[dataSessionId]
        if not session?
            throw new Meteor.Error "Data session not found: #{JSON.stringify dataSessionId}"

        for querySpec in addedQuerySpecs
            unless querySpec.modelName of J.models
                throw new Meteor.Error "Invalid modelName in querySpec:
                    #{J.util.toString querySpec}"

        actualAdded = []
        actualDeleted = []
        for querySpec in deletedQuerySpecs
            qsString = EJSON.stringify querySpec
            if session.querySpecSet().hasKey(qsString)
                actualDeleted.push querySpec
                session.querySpecSet().delete qsString
        for querySpec in addedQuerySpecs
            qsString = EJSON.stringify querySpec
            unless session.querySpecSet().hasKey(qsString)
                actualAdded.push qsString
                session.querySpecSet().setOrAdd qsString, true

        if actualAdded.length or actualDeleted.length
            J.assert not session.currentWrite?
            session.currentWrite = DDPServer._CurrentWriteFence.get().beginWrite()


Meteor.publish '_jdata', (dataSessionId) ->
    log = ->
        newArgs = ["[#{dataSessionId}]"].concat _.toArray arguments
        console.log.apply console, newArgs

    log 'publish _jdata'

    check dataSessionId, String
    session = dataSessions[dataSessionId] = J.Dict
        querySpecSet: J.Dict() # qsString: true
        mergedQuerySpecs: undefined

    mergedQuerySpecsVar = session.mergedQuerySpecs J.AutoVar(
        =>
            log "Recalc mergedQuerySpecsVar"
            mergedQuerySpecs = J.List()
            session.querySpecSet().forEach (rawQsString) ->
                # TODO: Fancier merge stuff
                rawQuerySpec = EJSON.parse rawQsString
                mergedQuerySpecs.push rawQuerySpec
            mergedQuerySpecs
    )


    observerByQuerySpecString = J.Dict()
    makeObserver = (querySpec) =>
        log "Make observer for: ", querySpec
        modelClass = J.models[querySpec.modelName]

        options = {}
        for optionName in ['sort', 'skip', 'limit']
            if querySpec[optionName]?
                options[optionName] = querySpec[optionName]

        # TODO: Interpret options.fields with fancy semantics

        cursor = modelClass.collection.find querySpec.selector, options

        observer = cursor.observeChanges
            added: (id, fields) =>
                log "ADDED:", querySpec, id, fields
                @added modelClass.collection._name, id, fields
            changed: (id, fields) =>
                log "CHANGED:", querySpec, id
                @changed modelClass.collection._name, id, fields
            removed: (id) =>
                log "REMOVED:", querySpec, id
                @removed modelClass.collection._name, id

        observer


    mergedSpecStringsVar = J.AutoVar(
        => session.mergedQuerySpecs().map (specDict) => EJSON.stringify specDict.toObj()
        (oldSpecStrings, newSpecStrings) =>
            diff = J.Dict.diff oldSpecStrings?.toArr() ? [], newSpecStrings.toArr()
            for specString in diff.added
                observerByQuerySpecString.setOrAdd specString, makeObserver EJSON.parse specString
            for specString in diff.deleted
                observerByQuerySpecString.get(specString).stop()

            log "Observers: #{EJSON.stringify (EJSON.parse spec for spec in newSpecStrings.toArr())}"

            if diff.added.length or diff.deleted.length
                session.currentWrite.committed()
                delete session.currentWrite
    )


    @onStop =>
        log 'Stop publish _jdata', dataSessionId
        mergedSpecStringsVar.stop()
        mergedQuerySpecsVar.stop()
        observerByQuerySpecString.forEach (querySpecString, observer) => observer.stop()
        delete dataSessions[dataSessionId]


    @ready()
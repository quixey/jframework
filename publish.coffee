###
    dataSessionId: J.Dict
        querySpecs: [
            {
                modelName:
                selector:
                fields:
                sort:
                skip:
                limit:
            }
        ]
###
dataSessions = {}

Meteor.methods
    _addDataQueries: (dataSessionId, querySpecs) ->
        console.log 'called _addDataQueries', dataSessionId, querySpecs

        session = dataSessions[dataSessionId]
        if not session?
            throw new Meteor.Error "Data session not found: #{JSON.stringify dataSessionId}"

        for querySpec in querySpecs
            unless querySpec.modelName of J.models
                throw new Meteor.Error "Invalid modelName in querySpec:
                    #{J.util.toString querySpec}"

        session.querySpecs().extend querySpecs


Meteor.publish '_jdata', (dataSessionId) ->
    log = ->
        newArgs = ["[#{dataSessionId}]"].concat _.toArray arguments
        console.log.apply console, newArgs

    log 'publish _jdata'

    check dataSessionId, String
    session = dataSessions[dataSessionId] = J.Dict
        querySpecs: J.List()
        mergedQuerySpecs: undefined

    mergedQuerySpecsVar = session.mergedQuerySpecs J.AutoVar(
        =>
            log "Recalc mergedQuerySpecsVar"
            mergedQuerySpecs = J.List()
            session.querySpecs().forEach (rawQuerySpec) ->
                # TODO: Fancier merge stuff
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

        cursor.observeChanges
            added: (id, fields) =>
                log "ADDED: ", querySpec, id, fields
                @added modelClass.collection._name, id, fields
            changed: (id, fields) =>
                log "CHANGED: ", querySpec, id
                @changed modelClass.collection._name, id, fields
            removed: (id) =>
                log "REMOVED: ", querySpec, id
                @removed modelClass.collection._name, id


    mergedSpecStringsVar = J.AutoVar(
        => session.mergedQuerySpecs().map (specDict) => EJSON.stringify specDict.toObj()
        (oldSpecStrings, newSpecStrings) =>
            diff = J.Dict.diff oldSpecStrings?.toArr() ? [], newSpecStrings.toArr()
            for specString in diff.added
                observerByQuerySpecString.setOrAdd specString, makeObserver EJSON.parse specString
            for specString in diff.deleted
                observerByQuerySpecString.get(specString).stop()

            log "Observers: #{EJSON.stringify (EJSON.parse spec for spec in newSpecStrings.toArr())}"
    )


    @onStop =>
        log 'Stop publish _jdata', dataSessionId
        mergedSpecStringsVar.stop()
        mergedQuerySpecsVar.stop()
        observerByQuerySpecString.forEach (querySpecString, observer) => observer.stop()
        delete dataSessions[dataSessionId]


    @ready()
Future = Npm.require 'fibers/future'

J._inMethod = new Meteor.EnvironmentVariable

J.methods = (methods) ->
    wrappedMethods = {}
    for methodName, methodFunc of methods
        do (methodName, methodFunc) ->
            wrappedMethods[methodName] = ->
                args = arguments
                J._inMethod.withValue true, =>
                    methodFunc.apply @, args

    Meteor.methods wrappedMethods


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
        currentQuery: <Future>
###
dataSessions = {}


Meteor.methods
    _updateDataQueries: (dataSessionId, addedQuerySpecs, deletedQuerySpecs) ->
        log = ->
            newArgs = ["[#{dataSessionId}]"].concat _.toArray arguments
            console.log.apply console, newArgs

        log '_updateDataQueries'
        if addedQuerySpecs.length
            log '    added:', J.util.stringify addedQuerySpecs
        if deletedQuerySpecs.length
            log '    deleted:', J.util.stringify deletedQuerySpecs

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
            session.currentQuery = new Future()
            session.currentQuery.wait()
            # This is the point of the DDP write fence. The problem is that
            # Meteor's write fence only blocks this method from returning.
            # It still unblocks in the sense that other methods can start
            # running, and that's a problem for a data query.

        log '..._updateDataQueries done'


Meteor.publish '_jdata', (dataSessionId) ->
    log = ->
        newArgs = ["[#{dataSessionId}]"].concat _.toArray arguments
        console.log.apply console, newArgs

    log 'publish _jdata'

    check dataSessionId, String
    session = dataSessions[dataSessionId] = J.Dict
        querySpecSet: J.Dict() # qsString: true
        mergedQuerySpecs: undefined

    mergedQuerySpecsVar = session.mergedQuerySpecs J.AutoVar 'mergedQuerySpecs',
        =>
            # log "Recalc mergedQuerySpecsVar"
            mergedQuerySpecs = J.List()
            session.querySpecSet().forEach (rawQsString) ->
                # TODO: Fancier merge stuff
                rawQuerySpec = EJSON.parse rawQsString
                mergedQuerySpecs.push rawQuerySpec
            mergedQuerySpecs

    observerByQsString = J.Dict()
    fieldsByModelIdQuery = {} # modelName: docId: fieldName: querySpecString: value
    makeObserver = (querySpec) =>
        # log "Make observer for: ", querySpec
        modelClass = J.models[querySpec.modelName]

        options = {}
        for optionName in ['sort', 'skip', 'limit']
            if querySpec[optionName]?
                options[optionName] = querySpec[optionName]

        # TODO: Interpret options.fields with fancy semantics

        cursor = modelClass.collection.find querySpec.selector, options

        qsString = EJSON.stringify querySpec

        observer = cursor.observeChanges
            added: (id, fields) =>
                # log querySpec, "server says ADDED:", id, fields

                if id not of (fieldsByModelIdQuery?[querySpec.modelName] ? {})
                    # log querySpec, "sending ADDED:", id, fields
                    @added modelClass.collection._name, id, fields

                fieldsByModelIdQuery[querySpec.modelName] ?= {}
                fieldsByModelIdQuery[querySpec.modelName][id] ?= {}
                for fieldName, value of fields
                    fieldsByModelIdQuery[querySpec.modelName][id][fieldName] ?= {}
                    fieldsByModelIdQuery[querySpec.modelName][id][fieldName][qsString] = value

            changed: (id, fields) =>
                # log querySpec, "server says CHANGED:", id, fields

                changedFields = {}

                for fieldName, value of fields
                    oldValue = _.values(fieldsByModelIdQuery[querySpec.modelName][id][fieldName] ? {})?[0]
                    fieldsByModelIdQuery[querySpec.modelName][id][fieldName] ?= {}
                    fieldsByModelIdQuery[querySpec.modelName][id][fieldName][qsString] = value
                    newValue = _.values(fieldsByModelIdQuery[querySpec.modelName][id][fieldName] ? {})?[0]
                    if not EJSON.equals oldValue, newValue
                        changedFields[fieldName] = value

                if not _.isEmpty changedFields
                    # log querySpec, "sending CHANGED:", id, changedFields
                    @changed modelClass.collection._name, id, changedFields

            removed: (id) =>
                # log querySpec, "server says REMOVED:", id

                changedFields = {}

                for fieldName in _.keys fieldsByModelIdQuery[querySpec.modelName][id]
                    oldValue = _.values(fieldsByModelIdQuery[querySpec.modelName][id][fieldName])[0]
                    delete fieldsByModelIdQuery[querySpec.modelName][id][fieldName][qsString]
                    newValue = _.values(fieldsByModelIdQuery[querySpec.modelName][id][fieldName])[0]
                    if not EJSON.equals oldValue, newValue
                        changedFields[fieldName] = newValue
                    if _.isEmpty fieldsByModelIdQuery[querySpec.modelName][id][fieldName]
                        delete fieldsByModelIdQuery[querySpec.modelName][id][fieldName]

                if _.isEmpty fieldsByModelIdQuery[querySpec.modelName][id]
                    delete fieldsByModelIdQuery[querySpec.modelName][id]
                    # log querySpec, "sending REMOVED:", id
                    @removed modelClass.collection._name, id
                else if not _.isEmpty changedFields
                    # log querySpec, "sending CHANGED:", id
                    @changed modelClass.collection._name, id, changedFields

        observer


    mergedSpecStringsVar = J.AutoVar 'mergedSpecStrings',
        (=>
            J.List session.mergedQuerySpecs().map (specDict) => EJSON.stringify specDict.toObj()
        ),
        ((oldSpecStrings, newSpecStrings) =>
            # console.log 'mergedSpec changed:'
            # console.log "      #{J.util.stringify oldSpecStrings}"
            # console.log "      #{J.util.stringify newSpecStrings}"
            diff = J.Dict.diff oldSpecStrings?.toArr() ? [], newSpecStrings.toArr()
            for qsString in diff.added
                observerByQsString.setOrAdd qsString, makeObserver EJSON.parse qsString
            for qsString in diff.deleted
                querySpec = EJSON.parse qsString
                log querySpec, 'STOPPED'

                observerByQsString.get(qsString).stop()
                observerByQsString.delete qsString

                modelClass = J.models[querySpec.modelName]
                for docId in _.keys fieldsByModelIdQuery[querySpec.modelName] ? {}
                    cursorValues = fieldsByModelIdQuery[querySpec.modelName][docId]

                    changedFields = {}
                    for fieldName in _.keys cursorValues
                        valueByQsString = cursorValues[fieldName]
                        oldValue = _.values(valueByQsString)[0]
                        delete valueByQsString[qsString]
                        newValue = _.values(valueByQsString)[0]
                        if not EJSON.equals oldValue, newValue
                            changedFields[fieldName] = newValue
                        if _.isEmpty valueByQsString
                            delete cursorValues[fieldName]

                    if _.isEmpty cursorValues
                        delete fieldsByModelIdQuery[querySpec.modelName][docId]
                        # log querySpec, "sending REMOVED", docId
                        @removed modelClass.collection._name, docId
                    else if not _.isEmpty changedFields
                        # log querySpec, "passing along CHANGED", docId, changedFields
                        @changed modelClass.collection._name, id, changedFields


            # log "Observers: #{EJSON.stringify (EJSON.parse spec for spec in newSpecStrings.toArr())}"

            if diff.added.length or diff.deleted.length
                session.currentQuery.return()
        )


    @onStop =>
        log 'Stop publish _jdata', dataSessionId
        mergedSpecStringsVar.stop()
        mergedQuerySpecsVar.stop()
        observerByQsString.forEach (querySpecString, observer) => observer.stop()
        delete dataSessions[dataSessionId]


    @ready()
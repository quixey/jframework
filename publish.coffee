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
            console.warn "Data session not found", dataSessionId
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
            # This part is instead of using the DDP write fence. The problem is that
            # Meteor's write fence only blocks this method from returning. It still
            # unblocks in the sense that other methods can start running, and that's
            # a problem for a data query.
            session.currentQuery = new Future()
            # The afterFlush sortKey of 0.8 gives the publish function time to stop
            # and start observers to achieve its new set of merged cursors, plus have
            # those cursors send their initial data to the client.
            Tracker.afterFlush(
                -> session.currentQuery.return()
                0.8
            )
            session.currentQuery.wait()

        log '..._updateDataQueries done'


Meteor.publish '_jdata', (dataSessionId) ->
    # Run the publisher in a computation so we can stop all its
    # AutoVars with a single command.

    sessionComp = Tracker.autorun (sessionComp) =>
        if not sessionComp.firstRun
            throw new Meteor.Error "Nothing should invalidate the
                publisher computation (other than stopping it)."

        publishJData.call @, dataSessionId

    @onStop =>
        console.log "[#{dataSessionId}] STOPPED"
        sessionComp.stop()
        delete dataSessions[dataSessionId]

    @ready()


publishJData = (dataSessionId) ->
    log = ->
        newArgs = ["[#{dataSessionId}]"].concat _.toArray arguments
        console.log.apply console, newArgs

    log 'publish _jdata'

    check dataSessionId, String

    # The set of active cursors and exactly what each has sent to the client
    fieldsByModelIdQuery = {} # modelName: docId: fieldName: querySpecString: value

    session = dataSessions[dataSessionId] = J.AutoDict "dataSessions[#{dataSessionId}]",
        querySpecSet: J.Dict() # qsString: true

        mergedQuerySpecs: => getMergedQuerySpecs session.querySpecSet()

        observerByQsString: J.AutoDict(
            "observerByQsString"

            => session.mergedQuerySpecs().map (specDict) => EJSON.stringify specDict.toObj()

            (qsString) => makeObserver EJSON.parse qsString

            (qsString, oldObserver, newObserver) =>
                querySpec = EJSON.parse qsString
                if newObserver?
                    J.assert oldObserver is undefined, "No reason for observer object to change."
                    return

                # Stopped an observer due to remerging
                log querySpec, "STOPPED"

                # Send updates to undo the effect that this cursor had on the client's
                # view of the overall data set.
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
                        log querySpec, "sending REMOVED", docId
                        @removed modelClass.collection._name, docId
                    else if not _.isEmpty changedFields
                        log querySpec, "passing along CHANGED", docId, changedFields
                        @changed modelClass.collection._name, id, changedFields
        )

    getMergedQuerySpecs = (querySpecSet) =>
        log "getMergedQuerySpecs"
        mergedQuerySpecs = J.List()
        querySpecSet.forEach (rawQsString) ->
            # TODO: Fancier merge stuff
            rawQuerySpec = EJSON.parse rawQsString
            mergedQuerySpecs.push rawQuerySpec
        mergedQuerySpecs

    makeObserver = (querySpec) =>
        log "Make observer for: ", querySpec

        modelClass = J.models[querySpec.modelName]

        options = {}
        for optionName in ['sort', 'skip', 'limit']
            if querySpec[optionName]?
                options[optionName] = querySpec[optionName]

        # TODO: Interpret options.fields with fancy semantics

        cursor = modelClass.collection.find querySpec.selector, options

        qsString = EJSON.stringify querySpec

        cursor.observeChanges
            added: (id, fields) =>
                log querySpec, "server says ADDED:", id, fields

                if id not of (fieldsByModelIdQuery?[querySpec.modelName] ? {})
                    # log querySpec, "sending ADDED:", id, fields
                    @added modelClass.collection._name, id, fields

                fieldsByModelIdQuery[querySpec.modelName] ?= {}
                fieldsByModelIdQuery[querySpec.modelName][id] ?= {}
                for fieldName, value of fields
                    fieldsByModelIdQuery[querySpec.modelName][id][fieldName] ?= {}
                    fieldsByModelIdQuery[querySpec.modelName][id][fieldName][qsString] = value

            changed: (id, fields) =>
                log querySpec, "server says CHANGED:", id, fields

                changedFields = {}

                for fieldName, value of fields
                    oldValue = _.values(fieldsByModelIdQuery[querySpec.modelName][id][fieldName] ? {})?[0]
                    fieldsByModelIdQuery[querySpec.modelName][id][fieldName] ?= {}
                    fieldsByModelIdQuery[querySpec.modelName][id][fieldName][qsString] = value
                    newValue = _.values(fieldsByModelIdQuery[querySpec.modelName][id][fieldName] ? {})?[0]
                    if not EJSON.equals oldValue, newValue
                        changedFields[fieldName] = value

                if not _.isEmpty changedFields
                    log querySpec, "sending CHANGED:", id, changedFields
                    @changed modelClass.collection._name, id, changedFields

            removed: (id) =>
                log querySpec, "server says REMOVED:", id

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
                    log querySpec, "sending REMOVED:", id
                    @removed modelClass.collection._name, id
                else if not _.isEmpty changedFields
                    log querySpec, "sending CHANGED:", id
                    @changed modelClass.collection._name, id, changedFields
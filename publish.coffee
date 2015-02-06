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

        console.log 'gonna extend'
        session.querySpecs().extend querySpecs
        console.log '...extended'


Meteor.publish '_jdata', (dataSessionId) ->
    console.log 'publish _jdata, sessionId=', dataSessionId, dataSessions

    check dataSessionId, String
    session = dataSessions[dataSessionId] = J.Dict
        querySpecs: J.List()

    mergedQuerySpecsVar = session.setOrAdd 'mergedQuerySpecs', J.AutoVar(
        =>
            console.log 'recalc mergedQuerySpecsVar'
            rawQuerySpecs = session.querySpecs().toArr()
            rawQuerySpecs.map _.identity
    )

    observerByQuerySpec = J.AutoDict(
        =>
            console.log 'recalc observerbyqueryspec'
            session.mergedQuerySpecs().forEach (spec) -> JSON.stringify spec.toObj()

        Meteor.bindEnvironment (encodedQuerySpec) =>
            console.log 'YO YO', encodedQuerySpec
            return "YO YO"

            querySpec = JSON.parse encodedQuerySpec
            console.log 'calc querySpec: ', querySpec

            modelClass = J.models[querySpec.modelName]

            options = {}
            for optionName in ['sort', 'skip', 'limit']
                if querySpec[optionName]?
                    options[optionName] = querySpec[optionName]

            # TODO: Interpret options.fields with fancy semantics

            cursor = modelClass.collection.find querySpec.selector, options

            cursor.observeChanges
                added: (id, fields) =>
                    @added modelClass.collection._name, id, fields
                changed: (id, fields) =>
                    @changed modelClass.collection._name, id, fields
                removed: (id) =>
                    @removed modelClass.collection._name, id

            console.log 'got cursor: ', cursor
            cursor
            # TODO: @ready

#        (encodedQuerySpec, oldObserver, newObserver) =>
#            console.log 'observerByQuerySpec onchange: ', arguments
#            oldObserver?.stop()
    )

    @onStop =>
        console.log 'Stop publish _jdata', dataSessionId
        mergedQuerySpecsVar.stop()
        observerByQuerySpec.forEach (querySpec, observer) => observer.stop()
        observerByQuerySpec.stop()
        delete dataSessions[dataSessionId]
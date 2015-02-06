###
    dataSessionId: J.Dict
        querySpecs: [
            {
                modelName:
                selector:
            }
        ]
###
dataSessions = {}


Meteor.methods
    _addDataQueries: (dataSessionId, querySpecs) ->
        session = dataSessions[dataSessionId]
        if not session?
            throw new Meteor.Error "Data session not found: #{JSON.stringify dataSessionId}"

        for querySpec in querySpecs
            unless querySpec.modelName of J.models
                throw new Meteor.Error "Invalid modelName in querySpec:
                    #{J.util.toString querySpec}"

        session.querySpecs.extend querySpecs


Meteor.publish '_jdata', (dataSessionId) ->
    check dataSessionId, String
    session = dataSessions[dataSessionId] = J.Dict
        querySpecs: J.List()
        mergedQuerySpecs: J.List()

    mergedQuerySpecsVar = J.AutoVar(
        =>
            rawQuerySpecs = session.querySpecs().toArr()

            mergedQuerySpecs = []
            rawQuerySpecs.forEach (rawQuerySpec) =>
                mergedQuerySpecs.push rawQuerySpec
            session.mergedQuerySpecs mergedQuerySpecs
    )

    observerByQuerySpec = J.AutoDict(
        => session.mergedQuerySpecs()
        (querySpec) =>
            modelClass = J.models[querySpec.modelName]

            options = {}
            for optionName in ['sort', 'skip', 'limit']
                if querySpec[optionName]?
                    options[optionName] = querySpec[optionName]

            # TODO: Interpret options.fields with fancy semantics

            cursor = modelClass.collection.find querySpec.selector, options

            cursor.observeChanges
    )

    @onStop =>
        mergedQuerySpecsVar.stop()
        delete dataSessions[dataSessionId]
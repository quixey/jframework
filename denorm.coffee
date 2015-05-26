###
    Copyright 2015, Quixey Inc.
    All rights reserved.

    Licensed under the Modified BSD License found in the
    LICENSE file in the root directory of this source tree.
###

J.denorm =
    _watchingQueries: false
    _watchedQuerySpecSet: null

    ensureAllReactiveWatcherIndexes: ->
        helper = (modelClass, reactiveName) ->
            for modelClassName, modelClass of J.models
                indexFieldsSpec = {}
                indexFieldsSpec["_reactives.#{reactiveName}.watching.modelName"] = 1
                indexFieldsSpec["_reactives.#{reactiveName}.watching.selector"] = 1
                # indexFieldsSpec["_reactives.#{reactiveName}.watching.selector._id"] = 1
                # indexFieldsSpec["_reactives.#{reactiveName}.watching.selector._id.$in"] = 1

                modelClass.collection._ensureIndex(
                    indexFieldsSpec
                    sparse: true
                )

        for modelClassName, modelClass of J.models
            for reactiveName, reactiveSpec of modelClass.reactiveSpecs
                if reactiveSpec.denorm
                    helper modelClass, reactiveName


    recalc: (instance, reactiveName) ->
        reactiveSpec = instance.modelClass.reactiveSpecs[reactiveName]

        @_watchedQuerySpecSet = watchedQuerySpecSet = {}
        @_watchingQueries = true

        value = reactiveSpec.val.call instance

        @_watchingQueries = false
        @_watchedQuerySpecSet = null

        console.log 'watched: ', watchedQuerySpecSet

        watchedQsStrings = J.util.sortByKey _.keys watchedQuerySpecSet
        watchedQuerySpecs = (
            EJSON.parse qsString for qsString in watchedQsStrings
        )

        setter = {}
        setter["_reactives.#{reactiveName}"] =
            val: J.Model._getEscapedSubdoc value
            watching: J.Model._getEscapedSubdoc watchedQuerySpecs
        instance.modelClass.update(
            instance._id
            $set: setter
        )


    resetWatchers: (modelName, instanceId, oldValues, newValues) ->
        ###
            Returns modelName: [(instance, reactiveName)]
        ###

        console.log 'resetWatchers', modelName, instanceId,
            'oldValues:', JSON.stringify(oldValues),
            'newValues', JSON.stringify(newValues)

        # Makes sure every fieldSpec in he watching-selector is consistent
        # with either oldValues or newValues
        subFieldSelectorMatcher = [
            selector: $type: 3 # object
        ]

        subFieldSelectorMatcher.push
            $or: [
                'selector._id': $in: [null, instanceId]
            ,
                'selector._id.*DOLLAR*in': $in: [instanceId]
            ]

        addClauses = (selectorPrefix, oldSubValues, newSubValues) =>
            subFieldNameSet = {}
            for subFieldName of oldSubValues
                subFieldNameSet[subFieldName] = true
            for subFieldName of newSubValues
                subFieldNameSet[subFieldName] = true

            for subFieldName of subFieldNameSet
                if selectorPrefix is 'selector'
                    selectorPath = "selector.#{J.Model.escapeDot subFieldName}"
                else
                    selectorPath = "#{selectorPrefix}*DOT*#{J.Model.escapeDot subFieldName}"

                oldValue = oldSubValues[subFieldName]
                newValue = newSubValues[subFieldName]

                term = $or: [{}, {}]
                term.$or[0][selectorPath] = $in: [null]
                term.$or[1]["#{selectorPath}.*DOLLAR*in"] = $in: []

                if oldValue?
                    term.$or[0][selectorPath].$in.push oldValue
                    term.$or[1]["#{selectorPath}.*DOLLAR*in"].$in.push oldValue
                if newValue? and not EJSON.equals oldValue, newValue
                    term.$or[0][selectorPath].$in.push newValue
                    term.$or[1]["#{selectorPath}.*DOLLAR*in"].$in.push newValue

                subFieldSelectorMatcher.push term

                if J.util.isPlainObject(oldValue) or J.util.isPlainObject(newValue)
                    addClauses(
                        selectorPath
                        if J.util.isPlainObject(oldValue) then oldValue else {}
                        if J.util.isPlainObject(newValue) then newValue else {}
                    )

        addClauses 'selector', oldValues, newValues

        # projectionSpecKeys makes sure one of the fieldspecs
        # that have a diffed value is present in the
        # watching-projection.
        relevantProjectionSpecKeys = []
        # TODO

        watchersByModelReactive = {} # modelName: reactiveName: [instanceId]
        for watcherModelName, watcherModelClass of J.models
            for reactiveName, reactiveSpec of watcherModelClass.reactiveSpecs
                if reactiveSpec.denorm
                    # TODO: add relevantProjectionSpecKeys logic here too
                    selector = {}
                    selector["_reactives.#{reactiveName}.watching"] =
                        $elemMatch:
                            modelName: modelName
                            $or: [
                                selector: $in: [null, instanceId]
                            ,
                                $and: subFieldSelectorMatcher
                            ]

                    console.log "***<#{watcherModelName}>.#{reactiveName}***"
                    # console.log "selector: #{JSON.stringify selector, null, 4}"

                    unsetter = {}
                    unsetter["_reactives.#{reactiveName}.val"] = 1
                    unsetter["_reactives.#{reactiveName}.watching"] = 1

                    watchersByModelReactive[watcherModelName] ?= {}
                    numWatchersReset = watchersByModelReactive[watcherModelName][reactiveName] = watcherModelClass.update(
                        selector
                    ,
                        $unset: unsetter
                    ,
                        multi: true
                    )
                    console.log "#{numWatchersReset} watchers reset\n"

        watchersByModelReactive





if Meteor.isServer then Meteor.startup ->
    J.methods
        testRecalc: (modelName, instanceId, reactiveName) ->
            modelClass = J.models[modelName]
            instance = modelClass.fetchOne instanceId
            if not instance
                throw new Meteor.Error "#{modelName} instance ##{instanceId} not found"

            J.denorm.recalc instance, reactiveName

        testResetWatchers: (modelName, instanceId, oldValues, newValues) ->
            J.denorm.resetWatchers modelName, instanceId, oldValues, newValues
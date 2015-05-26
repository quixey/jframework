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
        # TODO


    resetWatchers: (modelName, instanceId, oldValues, newValues) ->
        ###
            Returns modelName: [(instance, reactiveName)]
        ###

        subFieldSelectorMatcher =
            "selector._id": $in: [null, instanceId]
            "selector._id.$in": $in: [null, instanceId]
        relevantProjectionSpecKeys = []

        # TODO:
        # Make sure this watching-selector-matcher is saying
        # "every fieldspec in he watching-selector is consistent
        # with either oldValues or newValues"

        # Add a separate part that says "make sure one of the
        # fieldspecs that have a diffed value is present in the
        # watching-projection.

        addClauses = (selectorPrefix, oldSubValues, newSubValues) =>
            subFieldNameSet = {}
            for subFieldName of oldSubValues
                subFieldNameSet[subFieldName] = true
            for subFieldName of newSubValues
                subFieldNameSet[subFieldName] = true

            for subFieldName of subFieldNameSet
                selectorPath = "#{selectorPrefix}.#{J.Model.escapeDot subFieldName}"

                oldValue = oldSubValues[subFieldName]
                newValue = newSubValues[subFieldName]

                subFieldSelectorMatcher[selectorPath] = $in: [null]
                subFieldSelectorMatcher["#{selectorPath}.$in"] = $in: [null]
                if oldValue?
                    subFieldSelectorMatcher[selectorPath].$in.push oldValue
                    subFieldSelectorMatcher["#{selectorPath}.$in"].$in.push oldValue
                if newValue? and not EJSON.equals oldValue, newValue
                    subFieldSelectorMatcher[selectorPath].$in.push newValue
                    subFieldSelectorMatcher["#{selectorPath}.$in"].$in.push newValue

                if J.util.isPlainObject(oldValue) or J.util.isPlainObject(newValue)
                    addClauses(
                        selectorPath
                        if J.util.isPlainObject(oldValue) then oldValue else {}
                        if J.util.isPlainObject(newValue) then newValue else {}
                    )

        addClauses 'selector', oldValues, newValues


        watchersByModelReactive = {} # modelName: reactiveName: [instanceId]
        for watcherModelName, watcherModelClass of J.models
            for reactiveName, reactiveSpec of watcherModelClass.reactiveSpecs
                if reactiveSpec.denorm
                    selector = {}
                    selector["_reactives.#{reactiveName}.watching"] =
                        $elemMatch:
                            modelName: modelName
                            $and: [
                                $or: [
                                    selector: $in: [null, instanceId]
                                    subFieldSelectorMatcher
                                ]
                            ,
                                $or: [
                                    fields: null
                                ]
                            ]

                    console.log "***<#{watcherModelName}>.#{reactiveName}***"
                    console.log "selector: #{JSON.stringify selector, null, 4}"

                    unsetter = {}
                    unsetter["_reactives.#{reactiveName}.val"] = 1

                    watchersByModelReactive[watcherModelName] ?= {}
                    watcherIds = watchersByModelReactive[watcherModelName][reactiveName] = watcherModelClass.update(
                        selector
                        $unset: unsetter
                    )
                    console.log "Watchers: #{watcherIds}\n"

        watchersByModelReactive


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
            val: value
            watching: watchedQuerySpecs
        instance.modelClass.update(
            instance._id
            $set: setter
        )



if Meteor.isServer then Meteor.startup ->
    J.methods
        testDenorm: (modelName, instanceId, reactiveName) ->
            modelClass = J.models[modelName]
            instance = modelClass.fetchOne instanceId
            if not instance
                throw new Meteor.Error "#{modelName} instance ##{instanceId} not found"

            J.denorm.recalc instance, reactiveName

        testResetWatchers: (modelName, instanceId, oldValues, newValues) ->
            J.denorm.resetWatchers modelName, instanceId, oldValues, newValues
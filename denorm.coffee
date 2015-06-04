###
    Copyright 2015, Quixey Inc.
    All rights reserved.

    Licensed under the Modified BSD License found in the
    LICENSE file in the root directory of this source tree.
###

J._watchedQuerySpecSet = new Meteor.EnvironmentVariable

J.denorm =
    ensureAllReactiveWatcherIndexes: ->
        for reactiveModelName, reactiveModelClass of J.models
            for reactiveName, reactiveSpec of reactiveModelClass.reactiveSpecs
                continue if not reactiveSpec.denorm

                indexFieldsSpec = {}
                indexFieldsSpec["_reactives.#{reactiveName}.watching.modelName"] = 1
                indexFieldsSpec["_reactives.#{reactiveName}.watching.selector"] = 1
                # indexFieldsSpec["_reactives.#{reactiveName}.watching.selector._id"] = 1
                # indexFieldsSpec["_reactives.#{reactiveName}.watching.selector._id.$in"] = 1

                reactiveModelClass.collection._ensureIndex(
                    indexFieldsSpec
                    name: "_jReactiveWatcher_#{reactiveName}"
                    sparse: true
                )


    recalc: (instance, reactiveName, timestamp = new Date()) ->
        ###
            Sets _reactives.#{reactiveName}.val and .watchers
            Returns the recalculated value
        ###

        reactiveSpec = instance.modelClass.reactiveSpecs[reactiveName]

        value = null
        watchedQuerySpecSet = null

        console.log "Recalc <#{instance.modelClass.name} #{JSON.stringify instance._id}>.#{reactiveName}"

        J._watchedQuerySpecSet.withValue {}, =>
            value = reactiveSpec.val.call instance
            watchedQuerySpecSet = J._watchedQuerySpecSet.get()

        if value instanceof J.List
            value = value.toArr()
        else if value instanceof J.Dict
            value = value.toObj()

        # console.log "...done recalc <#{instance.modelClass.name} #{JSON.stringify instance._id}>.#{reactiveName}"

        watchedQsStrings = J.util.sortByKey _.keys watchedQuerySpecSet
        watchedQuerySpecs = (
            J.fetching.parseQs qsString for qsString in watchedQsStrings
        )

        setter = {}
        setter["_reactives.#{reactiveName}"] =
            val: J.Model._getEscapedSubdoc value
            watching: J.Model._getEscapedSubdoc watchedQuerySpecs
            ts: timestamp
        instance.modelClass.update(
            instance._id
            $set: setter
        )

        value


    resetWatchers: (modelName, instanceId, oldValues, newValues) ->
        ###
            Returns watcherModelName: reactiveName: [instanceId]
        ###

        modelClass = J.models[modelName]
        if modelClass.immutable
            return {}

        console.log 'resetWatchers', modelName, JSON.stringify(instanceId)

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
            # TODO: Handle more selectors besides just default (equality) and $in
            # e.g. $gt, $gte, $lt, $lte

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
                term.$or[0][selectorPath] =
                    $in: [null]
                term.$or[1]["#{selectorPath}.*DOLLAR*in"] =
                    $elemMatch: $in: [null]

                if oldValue?
                    term.$or[0][selectorPath].$in.push oldValue
                    term.$or[1]["#{selectorPath}.*DOLLAR*in"].$elemMatch.$in.push oldValue
                    if _.isArray oldValue then for elem in oldValue
                        term.$or[0][selectorPath].$in.push elem
                        term.$or[1]["#{selectorPath}.*DOLLAR*in"].$elemMatch.$in.push elem
                if newValue? and not EJSON.equals oldValue, newValue
                    term.$or[0][selectorPath].$in.push newValue
                    term.$or[1]["#{selectorPath}.*DOLLAR*in"].$elemMatch.$in.push newValue
                    if _.isArray newValue then for elem in newValue
                        term.$or[0][selectorPath].$in.push elem
                        term.$or[1]["#{selectorPath}.*DOLLAR*in"].$elemMatch.$in.push elem

                subFieldSelectorMatcher.push term

                if J.util.isPlainObject(oldValue) or J.util.isPlainObject(newValue)
                    addClauses(
                        selectorPath
                        if J.util.isPlainObject(oldValue) then oldValue else {}
                        if J.util.isPlainObject(newValue) then newValue else {}
                    )

        mutableOldValues = {}
        mutableNewValues = {}
        for fieldName, fieldSpec of modelClass.fieldSpecs
            continue if fieldSpec.immutable
            if fieldName of oldValues
                mutableOldValues[fieldName] = oldValues[fieldName]
            if fieldName of newValues
                mutableNewValues[fieldName] = newValues[fieldName]

        addClauses 'selector', mutableOldValues, mutableNewValues

        # projectionSpecKeys makes sure one of the fieldspecs
        # that have a diffed value is present in the
        # watching-projection.
        relevantProjectionSpecKeys = []
        # TODO

        watchersByModelReactive = {} # watcherModelName: reactiveName: [instanceId]
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

                    setter = {}
                    setter["_reactives.#{reactiveName}.ts"] = new Date()
                    unsetter = {}
                    unsetter["_reactives.#{reactiveName}.val"] = 1
                    unsetter["_reactives.#{reactiveName}.watching"] = 1

                    watchersByModelReactive[watcherModelName] ?= {}
                    numWatchersReset = watchersByModelReactive[watcherModelName][reactiveName] = watcherModelClass.update(
                        selector
                    ,
                        $set: setter
                        $unset: unsetter
                    ,
                        multi: true
                    )
                    if numWatchersReset
                        console.log "    <#{watcherModelName}>.#{reactiveName}:
                            #{numWatchersReset} watchers reset"
                        # console.log "selector: #{JSON.stringify selector, null, 4}"

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
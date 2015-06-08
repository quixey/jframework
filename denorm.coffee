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


    resetWatchers: (modelName, instanceId, oldValues, newValues, timestamp = new Date()) ->
        modelClass = J.models[modelName]

        console.log "resetWatchers <#{modelName} #{JSON.stringify(instanceId)}>
            #{JSON.stringify (oldValues: _.keys(oldValues), newValues: _.keys(newValues))}"

        makeWatcherMatcher = (instanceId, mutableOldValues, mutableNewValues) ->
            # Makes sure every fieldSpec in the watching-selector is consistent
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

            # We'll collect all the changed subFieldNames for later
            changedSubFieldSpecSet = {} # changedSubFieldSpec: true

            addSelectorClauses = (fieldSpecPrefix, oldSubValues, newSubValues) =>
                ###
                    1. Append clauses to subFieldSelectorMatcher so it restricts the
                       set of matched watchers to ones that ever returned this doc.

                    2. Mutate changedSubFieldNameSet for later
                ###

                # TODO: Handle more selectors besides just default (equality) and $in
                # e.g. $gt, $gte, $lt, $lte

                subFieldNameSet = {}
                for subFieldName of oldSubValues
                    subFieldNameSet[subFieldName] = true
                for subFieldName of newSubValues
                    subFieldNameSet[subFieldName] = true

                for subFieldName of subFieldNameSet
                    oldValue = oldSubValues[subFieldName]
                    newValue = newSubValues[subFieldName]

                    if not EJSON.equals oldValue, newValue
                        changedSubFieldSpecSet[subFieldName] = true

                    fieldSpec = fieldSpecPrefix.concat [subFieldName]
                    selectorKey = "selector.#{fieldSpec.map(J.Model.escapeDot).join('*DOT*')}"

                    term = $or: [{}, {}]
                    term.$or[0][selectorKey] =
                        $in: [null]
                    term.$or[1]["#{selectorKey}.*DOLLAR*in"] =
                        $elemMatch: $in: []

                    if oldValue?
                        term.$or[0][selectorKey].$in.push oldValue
                        term.$or[1]["#{selectorKey}.*DOLLAR*in"].$elemMatch.$in.push oldValue
                        if _.isArray oldValue then for elem in oldValue
                            term.$or[0][selectorKey].$in.push elem
                            term.$or[1]["#{selectorKey}.*DOLLAR*in"].$elemMatch.$in.push elem
                    if newValue? and not EJSON.equals oldValue, newValue
                        term.$or[0][selectorKey].$in.push newValue
                        term.$or[1]["#{selectorKey}.*DOLLAR*in"].$elemMatch.$in.push newValue
                        if _.isArray newValue then for elem in newValue
                            term.$or[0][selectorKey].$in.push elem
                            term.$or[1]["#{selectorKey}.*DOLLAR*in"].$elemMatch.$in.push elem

                    subFieldSelectorMatcher.push term

                    if J.util.isPlainObject(oldValue) or J.util.isPlainObject(newValue)
                        addSelectorClauses(
                            fieldSpec
                            if J.util.isPlainObject(oldValue) then oldValue else {}
                            if J.util.isPlainObject(newValue) then newValue else {}
                        )

            addSelectorClauses [], mutableOldValues, mutableNewValues

            for changedSubFieldSpec of changedSubFieldSpecSet
                oldValue = J.util.getField mutableOldValues, changedSubFieldSpec.join('.')
                newValue = J.util.getField mutableNewValues, changedSubFieldSpec.join('.')

                # TODO

            watcherMatcher =
                modelName: modelName
                $or: [
                    selector: $in: [null, instanceId]
                ,
                    $and: [
                        # The watcher's selector has a shot at ever matching
                        # the old or new document
                        $and: subFieldSelectorMatcher
                    ,
                        $or: [
                            # The watcher's set of docIds might have changed
                            # because its selector mentions a changed subfield
                            $or: changedSubfieldSelectorMatcher
                        ,
                            # The watcher's set of docIds might have changed
                            # because its sort key mentions a changed subfield
                            $or: changedSubfieldSortSpecMatcher
                        ,
                            # The watcher's set of field values might have changed
                            # because its projection mentions a changed subfield
                            $or: changedSubfieldProjectionMatcher
                        ]
                    ]
                ]

            watcherMatcher


        mutableOldValues = {}
        mutableNewValues = {}
        if not modelClass.immutable
            for fieldName, fieldSpec of modelClass.fieldSpecs
                continue if fieldSpec.immutable
                if fieldName of oldValues
                    mutableOldValues[fieldName] = oldValues[fieldName]
                if fieldName of newValues
                    mutableNewValues[fieldName] = newValues[fieldName]
        for reactiveName, reactiveSpec of modelClass.reactiveSpecs
            continue if not reactiveSpec.denorm
            if reactiveName of oldValues
                mutableOldValues[reactiveName] = oldValues[reactiveName]
            if reactiveName of newValues
                mutableNewValues[reactiveName] = newValues[reactiveName]
        if _.isEmpty(mutableOldValues) and _.isEmpty(mutableNewValues)
            return null

        watcherMatcher = makeWatcherMatcher instanceId, mutableOldValues, mutableNewValues

        resetCountByModelReactive = {} # "#{watcherModelName}.#{reactiveName}": resetCount
        resetOneWatcherDoc = (watcherModelName, watcherReactiveName) ->
            watcherModelClass = J.models[watcherModelName]
            # console.log "resetOneWatcherDoc: <#{watcherModelName}>.#{watcherReactiveName} watching <#{modelName}
                #{JSON.stringify instanceId}>"

            selector = {}
            selector["_reactives.#{watcherReactiveName}.ts"] = $lt: timestamp
            selector["_reactives.#{watcherReactiveName}.watching"] = $elemMatch: watcherMatcher

            setter = {}
            setter["_reactives.#{watcherReactiveName}.ts"] = timestamp

            unsetter = {}
            unsetter["_reactives.#{watcherReactiveName}.val"] = 1
            unsetter["_reactives.#{watcherReactiveName}.watching"] = 1

            resetCountByModelReactive["#{watcherModelName}.#{watcherReactiveName}"] ?= 0
            watcherModelClass.collection.rawCollection().findAndModify(
                selector
            ,
                []
            ,
                $set: setter
                $unset: unsetter
            ,
                (err, doc) ->
                    if err
                        console.error "Error while resetting #{watcherModelName}.#{watcherReactiveName}
                                    watchers of #{modelName}.#{JSON.stringify instanceId}:"
                        console.error err
                        return

                    if doc?
                        resetCountByModelReactive["#{watcherModelName}.#{watcherReactiveName}"] += 1

                        # Continue to reset one doc at a time until there are no more docs to reset
                        resetOneWatcherDoc watcherModelName, watcherReactiveName

                        # Also branch into resetting all docs watching this watching-reactive in this doc
                        watcherOldValues = {}
                        watcherOldValues[watcherReactiveName] = doc._reactives?[watcherReactiveName]?.val
                        watcherNewValues = {}
                        watcherNewValues[watcherReactiveName] = undefined
                        J.denorm.resetWatchers watcherModelName, doc._id, watcherOldValues, watcherNewValues, timestamp

                    else
                        numWatchersReset = resetCountByModelReactive["#{watcherModelName}.#{watcherReactiveName}"]
                        if numWatchersReset
                            console.log "    <#{watcherModelName}>.#{watcherReactiveName}:
                                #{numWatchersReset} watchers reset"
                            console.log "selector: #{JSON.stringify selector, null, 4}"
            )


        for watcherModelName, watcherModelClass of J.models
            for watcherReactiveName, watcherReactiveSpec of watcherModelClass.reactiveSpecs
                if watcherReactiveSpec.denorm
                    resetOneWatcherDoc watcherModelName, watcherReactiveName

        null



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

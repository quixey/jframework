# Copyright 2015, Quixey Inc.
# All rights reserved.
#
# Licensed under the Modified BSD License found in the
# LICENSE file in the root directory of this source tree.

J._watchedQuerySpecSet = new Meteor.EnvironmentVariable

# "#{modelName}.#{JSON.stringify instanceId}.#{reactiveName}": reactiveCalcObj
J._reactiveCalcsInProgress = {}

# [{modelName, instanceId, reactiveName, priority}]
J._reactiveCalcQueue = []

J._enqueueReactiveCalc = (modelName, instanceId, reactiveName, priority) ->
    modelClass = J.models[modelName]
    reactiveSpec = modelClass.reactiveSpecs[reactiveName]
    priority ?= reactiveSpec.priority ? 0.5

    reactiveKey = "#{modelName}.#{JSON.stringify instanceId}.#{reactiveName}"
    reactiveCalcObj = J._reactiveCalcsInProgress[reactiveKey]
    if reactiveCalcObj?
        # reactiveCalcObj is either already in the queue, or has been
        # dequeued and is currently being recalculated.
        if priority > reactiveCalcObj.priority
            reactiveCalcObj.priority = priority
            J.util.sortByKey J._reactiveCalcQueue, 'priority'
    else
        reactiveCalcObj =
            modelName: modelName
            instanceId: instanceId
            reactiveName: reactiveName
            priority: priority
        J._reactiveCalcsInProgress[reactiveKey] = reactiveCalcObj
        J._reactiveCalcQueue.push reactiveCalcObj
        J.util.sortByKey J._reactiveCalcQueue, 'priority'


J._dequeueReactiveCalc = ->
    return if J._reactiveCalcQueue.length is 0

    reactiveCalcObj = J._reactiveCalcQueue.pop()
    reactiveKey = "#{reactiveCalcObj.modelName}.#{JSON.stringify reactiveCalcObj.instanceId}.#{reactiveCalcObj.reactiveName}"

    modelClass = J.models[reactiveCalcObj.modelName]
    instance = modelClass.fetchOne reactiveCalcObj.instanceId

    # While this is recalculating, J._reactiveCalcsInProgress still contains reactiveKey
    # or else a different fiber could redundantly start the same recalc
    if instance?
        J.denorm.recalc instance, reactiveCalcObj.reactiveName

    delete J._reactiveCalcsInProgress[reactiveKey]



# This is a lightweight loop to make sure the highest-priority
# recalcs are always getting dequeued
Meteor.setInterval(
    J._dequeueReactiveCalc
    1000
)



J.denorm =
    ensureAllReactiveWatcherIndexes: ->
        for reactiveModelName, reactiveModelClass of J.models
            for reactiveName, reactiveSpec of reactiveModelClass.reactiveSpecs
                continue if not reactiveSpec.denorm

                indexFieldsSpec = {}
                indexFieldsSpec["_reactives.#{reactiveName}.dirty"] = 1
                indexFieldsSpec["_reactives.#{reactiveName}.watching.modelName"] = 1
                indexFieldsSpec["_reactives.#{reactiveName}.watching.selector._id.*DOLLAR*in"] = 1

                reactiveModelClass.collection._ensureIndex(
                    indexFieldsSpec
                    name: "_jReactiveWatcher_#{reactiveName}"
                    sparse: true
                )


    recalc: (instance, reactiveName, timestamp = new Date()) ->
        # Sets _reactives.#{reactiveName}.val and .watchers
        # Returns the recalculated value

        reactiveSpec = instance.modelClass.reactiveSpecs[reactiveName]
        if not reactiveSpec.denorm
            throw new Error "Can't recalc a non-denorm reactive:
                #{instance.modelClass.name}.#{reactiveName}"

        value = null
        watchedQuerySpecSet = null

        console.log "Recalc <#{instance.modelClass.name} #{JSON.stringify instance._id}>.#{reactiveName}"

        J._watchedQuerySpecSet.withValue {}, =>
            value = reactiveSpec.val.call instance
            watchedQuerySpecSet = J._watchedQuerySpecSet.get()

        if _.isArray value
            value = J.List(value).toArr()
        else if J.util.isPlainObject value
            value = J.Dict(value).toObj()
        else if value instanceof J.List
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
            dirty: false
        instance.modelClass.update(
            instance._id
            $set: setter
        )

        value


    resetWatchers: (modelName, instanceId, oldValues, newValues, timestamp = new Date(), callback) ->
        console.log "resetWatchers <#{modelName} #{JSON.stringify(instanceId)}>
            #{JSON.stringify (oldValues: _.keys(oldValues), newValues: _.keys(newValues))}"

        # Total number of running calls to resetWatchersHelper
        semaphore = 0

        semaAcquire = ->
            # console.log 'semaAcquire', semaphore - 1
            semaphore -= 1
        semaRelease = ->
            # console.log 'semaRelease', semaphore + 1
            semaphore += 1
            if semaphore is 0 then callback?()


        resetWatchersHelper = (modelName, instanceId, oldValues, newValues, timestamp) ->
            semaAcquire()

            lockSema = 0
            lockAcquire = ->
                # console.log 'lockAcquire', lockSema - 1
                lockSema -= 1
            lockRelease = ->
                # console.log 'lockRelease', lockSema + 1
                lockSema += 1
                if lockSema is 0 then semaRelease()


            modelClass = J.models[modelName]

            # console.log "resetWatchersHelper <#{modelName} #{JSON.stringify(instanceId)}>
                #{JSON.stringify (oldValues: _.keys(oldValues), newValues: _.keys(newValues))}"


            makeTermMatcher = (selectorKey, mustExist, possibleValues) ->
                equalityClause = {}
                equalityClause[selectorKey] =
                    $exists: true
                    $in: []

                inClause = {}
                inClause["#{selectorKey}.*DOLLAR*in"] =
                    $elemMatch: $in: []

                for value in possibleValues
                    equalityClause[selectorKey].$in.push value
                    inClause["#{selectorKey}.*DOLLAR*in"].$elemMatch.$in.push value
                    if _.isArray value then for elem in value
                        equalityClause[selectorKey].$in.push elem
                        inClause["#{selectorKey}.*DOLLAR*in"].$elemMatch.$in.push elem

                termMatcher = $or: [equalityClause, inClause]
                if not mustExist
                    doesntExistClause = {}
                    doesntExistClause[selectorKey] = $exists: false
                    termMatcher.$or.push doesntExistClause

                termMatcher


            makeWatcherMatcher = (instanceId, mutableOldValues, mutableNewValues) ->
                # Makes sure every fieldSpec in the watching-selector is consistent
                # with either oldValues or newValues
                subfieldSelectorMatcher = [
                    selector: $type: 3 # object
                ,
                    $or: [
                        'selector._id': $in: [null, instanceId]
                    ,
                        'selector._id.*DOLLAR*in': $in: [instanceId]
                    ]
                ]

                changedSubfieldSelectorMatcher = []
                changedSubfieldSortSpecMatcher = []
                changedSubfieldAlacarteProjectionMatcher = []
                changedSubfieldOverrideProjectionMatcher = []

                addSelectorClauses = (fieldSpecPrefix, oldSubValues, newSubValues) =>
                    # 1. Append clauses to subfieldSelectorMatcher so it restricts the
                    #    set of matched watchers to ones that ever returned this doc.
                    #
                    # 2. Mutate changedSubFieldNameSet for later
                    # FIXME

                    # TODO: Handle more selectors besides just default (equality) and $in
                    # e.g. $gt, $gte, $lt, $lte

                    subfieldNameSet = {}
                    for subfieldName of oldSubValues
                        subfieldNameSet[subfieldName] = true
                    for subfieldName of newSubValues
                        subfieldNameSet[subfieldName] = true

                    for subfieldName of subfieldNameSet
                        oldValue = oldSubValues[subfieldName]
                        newValue = newSubValues[subfieldName]
                        changed = not EJSON.equals oldValue, newValue

                        fieldSpec = fieldSpecPrefix.concat [subfieldName]
                        selectorKey = "selector.#{fieldSpec.map(J.Model.escapeDot).join('*DOT*')}"
                        projectionKey = "fields.#{fieldSpec.map(J.Model.escapeDot).join('*DOT*')}"
                        sortSpecKey = "sort.#{fieldSpec.map(J.Model.escapeDot).join('*DOT*')}"

                        possibleValues = []
                        if oldValue isnt undefined
                            possibleValues.push oldValue
                        if newValue isnt undefined and changed
                            possibleValues.push newValue

                        subfieldSelectorMatcher.push makeTermMatcher selectorKey, false, possibleValues

                        if changed
                            changedSubfieldSelectorMatcher.push makeTermMatcher selectorKey, true, possibleValues

                            term = {}
                            term[sortSpecKey] = $exists: true
                            changedSubfieldSortSpecMatcher.push term

                            term = {}
                            term[projectionKey] = true
                            changedSubfieldAlacarteProjectionMatcher.push term

                            term = {}
                            term[projectionKey] = true
                            if fieldSpecPrefix.length is 0
                                J.assert subfieldName of modelClass.fieldSpecs or subfieldName of modelClass.reactiveSpecs
                                if subfieldName of modelClass.fieldSpecs
                                    if modelClass.fieldSpecs[subfieldName].include ? true
                                        term[projectionKey] = $in: [null, true]
                                else
                                    if modelClass.reactiveSpecs[subfieldName].include ? false
                                        term[projectionKey] = $in: [null, true]
                            changedSubfieldOverrideProjectionMatcher.push term

                        if J.util.isPlainObject(oldValue) or J.util.isPlainObject(newValue)
                            addSelectorClauses(
                                fieldSpec
                                if J.util.isPlainObject(oldValue) then oldValue else {}
                                if J.util.isPlainObject(newValue) then newValue else {}
                            )

                addSelectorClauses [], mutableOldValues, mutableNewValues


                # We have to build watcherMatcher piece by piece because
                # we can't have an empty array of $or terms.
                changeConditions = []

                # The watcher's set of docIds might have changed
                # because its selector mentions a changed subfield
                if changedSubfieldSelectorMatcher.length
                    changeConditions.push
                        $or: changedSubfieldSelectorMatcher

                # The watcher's set of docIds might have changed
                # because its sort key mentions a changed subfield
                if changedSubfieldSortSpecMatcher.length
                    changeConditions.push
                        $or: changedSubfieldSortSpecMatcher

                # The watcher's set of field values might have changed
                # because its projection mentions a changed subfield
                if changedSubfieldAlacarteProjectionMatcher.length
                    changeConditions.push
                        'fields._': false
                        $or: changedSubfieldAlacarteProjectionMatcher
                if changedSubfieldOverrideProjectionMatcher.length
                    changeConditions.push
                        'fields._': $in: [null, true]
                        $or: changedSubfieldOverrideProjectionMatcher

                watcherMatcher =
                    modelName: modelName
                    $and: [
                        # The watcher's selector has a shot at ever matching
                        # the old or new document
                        $or: [
                            selector: $in: [null, instanceId]
                        ]
                    ]
                if subfieldSelectorMatcher.length
                    watcherMatcher.$and[0].$or.push
                        $and: subfieldSelectorMatcher
                if changeConditions.length
                    watcherMatcher.$and.push
                        $or: changeConditions

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
                watcherReactiveSpec = watcherModelClass.reactiveSpecs[watcherReactiveName]
                # console.log "resetOneWatcherDoc: <#{watcherModelName}>.#{watcherReactiveName} watching <#{modelName}
                    #{JSON.stringify instanceId}>"

                selector = {}
                selector["_reactives.#{watcherReactiveName}.dirty"] = false
                selector["_reactives.#{watcherReactiveName}.ts"] = $lt: timestamp
                selector["_reactives.#{watcherReactiveName}.watching"] = $elemMatch: watcherMatcher

                setter = {}
                setter["_reactives.#{watcherReactiveName}.ts"] = timestamp
                setter["_reactives.#{watcherReactiveName}.dirty"] = true

                resetCountByModelReactive["#{watcherModelName}.#{watcherReactiveName}"] ?= 0
                watcherModelClass.collection.rawCollection().findAndModify(
                    selector
                ,
                    []
                ,
                    $set: setter
                ,
                    Meteor.bindEnvironment (err, doc) ->
                        if err
                            console.error "Error while resetting #{watcherModelName}.#{watcherReactiveName}
                                watchers of #{modelName}.#{JSON.stringify instanceId}:"
                            console.error err
                            lockRelease()
                            return

                        if doc?
                            resetCountByModelReactive["#{watcherModelName}.#{watcherReactiveName}"] += 1

                            if watcherReactiveSpec.selectable
                                # Selectable reactives must stay updated
                                priority = (watcherReactiveSpec.priority ? 0.5) / 10
                                J._enqueueReactiveCalc watcherModelName, doc._id, watcherReactiveName, priority

                            # Continue to reset one doc at a time until there are no more docs to reset
                            resetOneWatcherDoc watcherModelName, watcherReactiveName

                            # Also branch into resetting all docs watching this watching-reactive in this doc
                            watcherOldValues = {}
                            watcherOldValues[watcherReactiveName] = doc._reactives?[watcherReactiveName]?.val
                            watcherNewValues = {}
                            watcherNewValues[watcherReactiveName] = undefined
                            resetWatchersHelper watcherModelName, doc._id, watcherOldValues, watcherNewValues, timestamp

                        else
                            numWatchersReset = resetCountByModelReactive["#{watcherModelName}.#{watcherReactiveName}"]
                            if numWatchersReset
                                console.log "    <#{watcherModelName}>.#{watcherReactiveName}:
                                    #{numWatchersReset} watchers reset"
                                # console.log "selector: #{JSON.stringify selector, null, 4}"

                            lockRelease()
                )


            for watcherModelName, watcherModelClass of J.models
                for watcherReactiveName, watcherReactiveSpec of watcherModelClass.reactiveSpecs
                    if watcherReactiveSpec.denorm
                        lockAcquire()
                        resetOneWatcherDoc watcherModelName, watcherReactiveName

            if lockSema is 0 then semaRelease()

            null


        resetWatchersHelper modelName, instanceId, oldValues, newValues, timestamp


Meteor.startup ->
    J.methods
        recalc: (modelName, instanceId, reactiveName) ->
            modelClass = J.models[modelName]
            instance = modelClass.fetchOne instanceId
            if not instance
                throw new Meteor.Error "#{modelName} instance ##{instanceId} not found"

            J.denorm.recalc instance, reactiveName

        fixMissingReactives: (modelName, reactiveName) ->
            modelClass = J.models[modelName]
            selector = {}
            selector["_reactives.#{reactiveName}.dirty"] = $ne: false
            while true
                instances = modelClass.find(
                    selector
                ,
                    limit: 100
                ).fetch()
                break if instances.length is 0

                console.log "Fixing batch of #{instances.length} missing reactives"
                for instance in instances
                    J.denorm.recalc instance, reactiveName

            null

        resetWatchers: (modelName, instanceId, oldValues, newValues) ->
            J.denorm.resetWatchers modelName, instanceId, oldValues, newValues

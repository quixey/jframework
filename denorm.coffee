# Copyright 2015, Quixey Inc.
# All rights reserved.
#
# Licensed under the Modified BSD License found in the
# LICENSE file in the root directory of this source tree.

Future = Npm.require 'fibers/future'

J._watchedQuerySpecSet = new Meteor.EnvironmentVariable

# "#{modelName}.#{JSON.stringify instanceId}.#{reactiveName}": reactiveCalcObj
J._reactiveCalcsInProgress = {}

# [{modelName, instanceId, reactiveName, priority}]
J._reactiveCalcQueue = []


Meteor.setInterval(
    -> J.denorm._dequeueReactiveCalc()
    100
)



class J.ExpirableValue
    constructor: (@expiryTime, @value) ->


J.expireAtTime = (expiryTime, value) ->
    if _.isNumber(expiryTime)
        expiryTime = new Date(1000 * (new Date().getTime() / 1000 + expiryTime))
    unless expiryTime instanceof Date
        throw new Error "Invalid expiryTime: #{expiryTime}"
    new J.ExpirableValue expiryTime, value


J.denorm =
    _enqueueReactiveCalc: (modelName, instanceId, reactiveName, priority, denormCallback) ->
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
                future: new Future
                denormCallback: denormCallback
            J._reactiveCalcsInProgress[reactiveKey] = reactiveCalcObj
            J._reactiveCalcQueue.unshift reactiveCalcObj
            J.util.sortByKey J._reactiveCalcQueue, 'priority'

        reactiveCalcObj


    _dequeueReactiveCalc: ->
        return if J._reactiveCalcQueue.length is 0

        if false
            console.log "DEQUEUE"
            for reactiveCalcObj, i in J._reactiveCalcQueue
                reactiveKey = "#{reactiveCalcObj.modelName}.#{JSON.stringify reactiveCalcObj.instanceId}.#{reactiveCalcObj.reactiveName}"
                console.log "    Calc ##{i}: #{reactiveKey}"
                console.log "        Priority: #{reactiveCalcObj.priority}"

        reactiveCalcObj = J._reactiveCalcQueue.pop()
        reactiveKey = "#{reactiveCalcObj.modelName}.#{JSON.stringify reactiveCalcObj.instanceId}.#{reactiveCalcObj.reactiveName}"

        modelClass = J.models[reactiveCalcObj.modelName]
        instance = modelClass.fetchOne(
            reactiveCalcObj.instanceId
            fields: J.fetching.makeFullProjection modelClass
        )

        # While this is recalculating, J._reactiveCalcsInProgress still contains reactiveKey
        # or else a different fiber could redundantly start the same recalc
        if instance?
            value = J.denorm.recalc instance, reactiveCalcObj.reactiveName, new Date(), reactiveCalcObj.denormCallback

        delete J._reactiveCalcsInProgress[reactiveKey]

        reactiveCalcObj.future.return value
        null


    ensureAllReactiveWatcherIndexes: ->
        for reactiveModelName, reactiveModelClass of J.models
            for reactiveName, reactiveSpec of reactiveModelClass.reactiveSpecs
                continue if not reactiveSpec.denorm

                indexFieldsSpec = {}
                indexFieldsSpec["_reactives.#{reactiveName}.watching.modelName"] = 1
                indexFieldsSpec["_reactives.#{reactiveName}.watching.selector._id.*DOLLAR*in"] = 1

                reactiveModelClass.collection._ensureIndex(
                    indexFieldsSpec
                    name: "_jReactiveWatcher_#{reactiveName}__id"
                    sparse: true
                )


    recalc: (instance, reactiveName, timestamp = new Date(), denormCallback) ->
        # Sets _reactives.#{reactiveName}.val and .watchers
        # Returns the recalculated value

        reactiveSpec = instance.modelClass.reactiveSpecs[reactiveName]
        if not reactiveSpec.denorm
            throw new Error "Can't recalc a non-denorm reactive:
                #{instance.modelClass.name}.#{reactiveName}"

        console.log "Recalc <#{instance.modelClass.name} #{JSON.stringify instance._id}>.#{reactiveName}"
        if J._reactiveCalcQueue.length > 0
            console.log "    (#{J._reactiveCalcQueue.length} more in queue)"

        oldDoc = instance.toDoc()
        oldDoc._reactives = instance._reactives

        watchedQuerySpecSet = null # watchedQsString: true
        unwrappedValue = undefined
        expiryTime = undefined
        J._watchedQuerySpecSet.withValue {}, =>
            rawValue = reactiveSpec.val.call instance
            if rawValue instanceof J.ExpirableValue
                unwrappedValue = J.Var.deepUnwrap rawValue.value
                expiryTime = rawValue.expiryTime
            else
                unwrappedValue = J.Var.deepUnwrap rawValue
                expiryTime = new Date('2020-01-01')

            watchedQuerySpecSet = J._watchedQuerySpecSet.get()

        escapedSubdoc = J.Model._getEscapedSubdoc unwrappedValue

        # denormCallback=false means the caller will worry about doing resetWatchers later
        # Otherwise denormCallback=null or denormCallback=<function>
        if denormCallback isnt false
            if EJSON.equals escapedSubdoc, oldDoc._reactives[reactiveName]?.val
                Future.task(
                    ->
                        denormCallback?()
                ).detach()
            else
                newDoc = _.clone oldDoc
                newDoc._reactives = _.clone oldDoc._reactives
                newDoc._reactives[reactiveName] =
                    val: escapedSubdoc
                J.denorm.resetWatchers instance.modelClass.name, instance._id, oldDoc, newDoc, timestamp, denormCallback

        console.log "...done recalc <#{instance.modelClass.name} #{JSON.stringify instance._id}>.#{reactiveName}"

        watchedQsStrings = J.util.sortByKey _.keys watchedQuerySpecSet
        watchedQuerySpecs = (
            J.fetching.parseQs qsString for qsString in watchedQsStrings
        )

        mergedWatchedQuerySpecs = J.fetching.getMerged watchedQuerySpecs

        # Change {selector: X} to {selector: $in: [X]} to be able to query on just
        # _reactives.#{reactiveName}.watching.#{selector}.*DOLLAR*in.
        for qs in mergedWatchedQuerySpecs
            if qs.selector?
                for fieldSpec, fieldMatcher of qs.selector
                    if not J.util.isPlainObject fieldMatcher
                        qs.selector[fieldSpec] = $in: [fieldMatcher]

        console.log "...merged #{watchedQuerySpecs.length} down to #{mergedWatchedQuerySpecs.length}"

        setter = {}
        setter["_reactives.#{reactiveName}"] =
            val: escapedSubdoc
            watching: J.Model._getEscapedSubdoc mergedWatchedQuerySpecs
            ts: timestamp
            expire: expiryTime
        instance.modelClass.update(
            instance._id
            $set: setter
        )

        console.log "...done with all of recalc <#{instance.modelClass.name} #{JSON.stringify instance._id}>.#{reactiveName}"

        J.Var.wrap unwrappedValue


    resetWatchers: (modelName, instanceId, oldDoc, newDoc, timestamp = new Date(), callback) ->
        # Total number of running calls to resetWatchersHelper
        semaphore = 0

        semaAcquire = ->
            # console.log 'semaAcquire', semaphore - 1
            semaphore -= 1
        semaRelease = ->
            # console.log 'semaRelease', semaphore + 1
            semaphore += 1
            if semaphore is 0
                console.log "...resetWatchers <#{modelName} #{JSON.stringify(instanceId)}> done"
                callback?()


        resetWatchersHelper = (modelName, instanceId, oldDoc, newDoc, timestamp) ->
            semaAcquire()

            modelClass = J.models[modelName]

            makeTermMatcher = (selectorKey, mustExist, possibleValues) ->
                usablePossibleValues = []

                for value in possibleValues
                    # NOTE: We don't support equality matching on objects
                    continue if J.util.isPlainObject value

                    if _.isArray value
                        # Let's not support equality matching on entire arrays;
                        # only the elements within them.
                    else
                        usablePossibleValues.push value

                return null if usablePossibleValues.length is 0

                if mustExist
                    termMatcher = {}
                    termMatcher["#{selectorKey}.*DOLLAR*in"] = $elemMatch: $in: usablePossibleValues
                else
                    termMatcher = $or: [{}, {}]
                    termMatcher.$or[0]["#{selectorKey}.*DOLLAR*in"] = null
                    termMatcher.$or[1]["#{selectorKey}.*DOLLAR*in"] = $elemMatch: $in: usablePossibleValues

                termMatcher


            changedFieldSpecs = []

            makeWatcherMatcher = (instanceId, mutableOldValues, mutableNewValues, isInsertOrDelete) ->
                # Makes sure every fieldSpec in the watching-selector is consistent
                # with either oldValues or newValues
                subfieldSelectorMatcher = [
                    'selector._id.*DOLLAR*in': $in: [null, instanceId]
                ]

                changedSubfieldSelectorMatcher = []
                changedSubfieldSortSpecMatcher = []
                changedSubfieldAlacarteProjectionMatcher = []
                changedSubfieldOverrideProjectionMatcher = []

                addSelectorClauses = (fieldSpecPrefix, oldSubValues, newSubValues) =>
                    # Append clauses to subfieldSelectorMatcher so it restricts the
                    # set of matched watchers to ones that ever returned this doc.
                    # Also append clauses to the other changedSubfield*Matcher lists.

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
                        selectorKey = "selector.#{J.Model.escapeDot fieldSpec.map(J.Model.escapeDot).join('.')}"
                        projectionKey = "fields.#{J.Model.escapeDot fieldSpec.map(J.Model.escapeDot).join('.')}"
                        sortSpecKey = "sort.#{J.Model.escapeDot fieldSpec.map(J.Model.escapeDot).join('.')}"

                        if fieldSpec[0] of modelClass.fieldSpecs
                            selectable = modelClass.fieldSpecs[fieldSpec[0]].selectable ? true
                            watchable = modelClass.fieldSpecs[fieldSpec[0]].watchable ? modelClass.watchable
                        else
                            selectable = modelClass.reactiveSpecs[fieldSpec[0]].selectable ? false
                            watchable = modelClass.reactiveSpecs[fieldSpec[0]].watchable ? modelClass.watchable

                        possibleValues = []
                        if oldValue isnt undefined
                            possibleValues.push oldValue
                        if newValue isnt undefined and changed
                            possibleValues.push newValue

                        if selectable
                            termMatcher = makeTermMatcher selectorKey, false, possibleValues
                            if termMatcher? then subfieldSelectorMatcher.push termMatcher

                        if changed
                            if selectable
                                termMatcher = makeTermMatcher selectorKey, true, possibleValues
                                if termMatcher? then changedSubfieldSelectorMatcher.push termMatcher

                            if selectable
                                term = {}
                                term[sortSpecKey] = $exists: true
                                changedSubfieldSortSpecMatcher.push term

                            if watchable
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

                    # The watcher's selector has a shot at ever matching
                    # the old or new document
                    $and: subfieldSelectorMatcher

                if changeConditions.length is 0
                    return null

                if not isInsertOrDelete
                    watcherMatcher.$and.push
                        $or: changeConditions

                watcherMatcher

            isInsertOrDelete = oldDoc._id? isnt newDoc._id?

            mutableOldValues = {}
            mutableNewValues = {}
            for fieldName, fieldSpec of modelClass.fieldSpecs
                mutableOldValues[fieldName] = oldDoc[fieldName]
                mutableNewValues[fieldName] = newDoc[fieldName]
            for reactiveName, reactiveSpec of modelClass.reactiveSpecs
                continue if not reactiveSpec.denorm
                mutableOldValues[reactiveName] = oldDoc._reactives?[reactiveName]?.val
                mutableNewValues[reactiveName] = newDoc._reactives?[reactiveName]?.val

            changedFieldSpecs = []
            for fieldOrReactiveName of mutableOldValues
                if not EJSON.equals mutableOldValues[fieldOrReactiveName], mutableNewValues[fieldOrReactiveName]
                    changedFieldSpecs.push fieldOrReactiveName

            watcherMatcher = makeWatcherMatcher instanceId, mutableOldValues, mutableNewValues, isInsertOrDelete
            console.log "ResetWatchersHelper: <#{modelName} #{JSON.stringify instanceId}> with changes to
                #{JSON.stringify changedFieldSpecs}#{if isInsertOrDelete then ' (insert/delete)' else ''}"

            if not watcherMatcher?
                semaRelease()
                return null

            watcherMatcherLength = JSON.stringify(watcherMatcher).length
            if watcherMatcherLength > 10000
                console.warn "***watcherMatcher for <#{modelName} #{JSON.stringify instanceId}>
                    #{JSON.stringify _.keys mutableOldValues} is #{watcherMatcherLength} chars long"
                console.log J.util.stringifyBrief watcherMatcher

            resetCountByModelReactive = {} # "#{watcherModelName}.#{reactiveName}": resetCount
            resetDebugsByModelReactive = {} # "#{watcherModelName}.#{reactiveName}": [debugStrings]
            resetWatcherDocs = (watcherModelName, watcherReactiveName) ->
                watcherModelClass = J.models[watcherModelName]
                watcherReactiveSpec = watcherModelClass.reactiveSpecs[watcherReactiveName]
                console.log "resetWatcherDocs: <#{watcherModelName}>.#{watcherReactiveName} watching <#{modelName}
                    #{JSON.stringify instanceId}>"

                selector = {}
                selector["_reactives.#{watcherReactiveName}.expire"] = $gt: timestamp
                selector["_reactives.#{watcherReactiveName}.ts"] = $lt: timestamp
                selector["_reactives.#{watcherReactiveName}.watching"] = $elemMatch: watcherMatcher

                setter = {}
                setter["_reactives.#{watcherReactiveName}.ts"] = timestamp
                setter["_reactives.#{watcherReactiveName}.expire"] = timestamp

                resetCountByModelReactive["#{watcherModelName}.#{watcherReactiveName}"] ?= 0
                resetDebugsByModelReactive["#{watcherModelName}.#{watcherReactiveName}"] ?= []

                rawCollection = watcherModelClass.collection.rawCollection()
                syncFindAndModify = Meteor.wrapAsync rawCollection.findAndModify, rawCollection

                while true
                    oldWatcherDoc = syncFindAndModify(
                        selector
                        []
                        $set: setter
                    )
                    break if not oldWatcherDoc?

                    resetCountByModelReactive["#{watcherModelName}.#{watcherReactiveName}"] += 1
                    resetDebugsByModelReactive["#{watcherModelName}.#{watcherReactiveName}"].push oldWatcherDoc._id

                    shouldRecalc = false
                    for dataSessionId, fieldsByModelIdQuery of J._dataSessionFieldsByModelIdQuery
                        for qsString, reactivesObj of fieldsByModelIdQuery[watcherModelName]?[oldWatcherDoc._id]?._reactives ? {}
                            if watcherReactiveName of reactivesObj
                                shouldRecalc = true
                                break
                        break if shouldRecalc
                    if shouldRecalc
                        console.log "YES currently being published: <#{watcherModelName} #{JSON.stringify oldWatcherDoc._id}>.#{watcherReactiveName}"
                    else
                        console.log "#{if watcherReactiveSpec.selectable then '~' else ''}NOT currently being published: <#{watcherModelName} #{JSON.stringify oldWatcherDoc._id}>.#{watcherReactiveName}"
                    if watcherReactiveSpec.selectable
                        # Selectable reactives must stay updated
                        shouldRecalc = true

                    newWatcherDoc = _.clone oldWatcherDoc
                    newWatcherDoc._reactives = _.clone oldWatcherDoc._reactives
                    delete newWatcherDoc._reactives[watcherReactiveName]

                    # Also branch into resetting all docs watching this watching-reactive in this doc
                    if shouldRecalc
                        # Recalc will take care of invalidation propagation and call resetWatchers
                        J.denorm._enqueueReactiveCalc watcherModelName, oldWatcherDoc._id, watcherReactiveName
                    else
                        # Aggressively propagate the reset so that other recalcs won't use the potentially-about-
                        # to-change value, even though the value might not actually change once it recalculates
                        Future.task(
                            do (oldWatcherDoc, newWatcherDoc) -> ->
                                resetWatchersHelper watcherModelName, oldWatcherDoc._id, oldWatcherDoc, newWatcherDoc, timestamp
                        ).detach()

                numWatchersReset = resetCountByModelReactive["#{watcherModelName}.#{watcherReactiveName}"]
                resetDebugs = resetDebugsByModelReactive["#{watcherModelName}.#{watcherReactiveName}"]
                if numWatchersReset
                    console.log "    <#{watcherModelName}>.#{watcherReactiveName}:
                        #{numWatchersReset} watchers reset by saving <#{modelName} #{JSON.stringify instanceId}>: #{JSON.stringify resetDebugs}"
                    # console.log "selector: #{JSON.stringify selector, null, 4}"

            for watcherModelName, watcherModelClass of J.models
                for watcherReactiveName, watcherReactiveSpec of watcherModelClass.reactiveSpecs
                    if watcherReactiveSpec.denorm and watcherReactiveSpec.autoDirty? and (
                        (modelName in watcherReactiveSpec.autoDirty) or
                        (isInsertOrDelete and "#{modelName}._id" in watcherReactiveSpec.autoDirty) or
                        _.any(
                            for fieldOrReactiveName in changedFieldSpecs
                                "#{modelName}.#{fieldOrReactiveName}" in watcherReactiveSpec.autoDirty
                        )
                    )
                        resetWatcherDocs watcherModelName, watcherReactiveName

            semaRelease()

            null


        resetWatchersHelper modelName, instanceId, oldDoc, newDoc, timestamp


Meteor.startup ->
    J.methods
        recalc: (modelName, instanceId, reactiveName) ->
            modelClass = J.models[modelName]
            instance = modelClass.fetchOne instanceId
            if not instance?
                throw new Meteor.Error "#{modelName} instance ##{instanceId} not found"

            reactiveCalcObj = J.denorm._enqueueReactiveCalc modelName, instanceId, reactiveName
            reactiveCalcObj.future.wait()

        fixMissingReactives: (modelName, reactiveName) ->
            modelClass = J.models[modelName]
            selector = $or: [{}, {}]
            selector.$or[0]["_reactives.#{reactiveName}.expire"] =
                $exists: false
            selector.$or[1]["_reactives.#{reactiveName}.expire"] =
                $exists: true
                $lt: new Date()

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

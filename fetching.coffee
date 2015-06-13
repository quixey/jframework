# Copyright 2015, Quixey Inc.
# All rights reserved.
#
# Licensed under the Modified BSD License found in the
# LICENSE file in the root directory of this source tree.

# Projection semantics of querySpec.fields:
#     "_" is a magic boolean key considered true by default.
#     When true, the querySpec.fields object extends the
#     model's set of field and reactive inclusion defaults.
#     When false, the querySpec.fields object represents the
#     whole set of field inclusions being requested.
#
# E.g. a model with these definitions...
#     fields: # included by default
#         a: {}
#         b: include: false
#         c: {}
#     reactives: # not-included by default
#         d: {}
#         e: include: true
#
# ...would have this mapping from querySpec.fields to included fields:
#     _: false
#         []
#
#     {} or _: true
#         ['a', 'c', 'e']
#
#     a: true
#         ['a', 'c', 'e']
#
#     _: false, a: true
#         ['a']
#
#     a: false
#         ['c', 'e']
#
#     b: true
#         ['a', 'b', 'c', 'e']
#
#     e: false
#         ['a', 'c']
#
#     'a.x.y': true, c: false
#         ['a', 'a.x.y', 'e']
#
#     _: false, 'a.x.y': true, c: false
#         ['a.x.y']


J.fetching = {}

if Meteor.isClient then _.extend J.fetching,
    SESSION_ID: "#{parseInt Math.random() * 1000000}"

    _requestInProgress: false

    ###
        Latest client-side state and whether it's changed since we
        last called the server's update method

    ###

    # Each computation maintains its own constantly-merged set of querySpecs
    # which union into the global _unmergedQsSet, and that gets merged into the
    # global _mergedQsSet.
    _qsByRequester: {} # computationId: querySpecString: true
    _requestersByQs: {} # querySpecString: {computationId: computation}
    _requestsChanged: false

    # Snapshot of what the cursors will be after the next _updateDataQueries returns
    _nextUnmergedQsSet: {} # querySpecString: true
    _nextMergedQsSet: {}

    # Snapshot of what we last successfully asked the server for
    _unmergedQsSet: {} # mergedQuerySpecString: true
    _mergedQsSet: {} # mergedQuerySpecString: true


_.extend J.fetching,
    _addComputationQsRequest: (computation, qs) ->
        qsString = @stringifyQs qs

        @_qsByRequester[computation._id] ?= {}
        if qsString of @_qsByRequester[computation._id]
            # Special case of _qsByRequester[computation._id]
            # being unchanged after remerging
            return

        oldQsStrings = _.keys @_qsByRequester[computation._id]
        @_qsByRequester[computation._id][qsString] = true
        @_qsByRequester[computation._id] = J.util.makeSet(
            @getMerged (@parseQs qss for qss of @_qsByRequester[computation._id])
            (qs) => @stringifyQs qs
        )
        newQsStrings = _.keys @_qsByRequester[computation._id]
        qsStringsDiff = J.util.diffStrings oldQsStrings, newQsStrings
        unless qsStringsDiff.added.length or qsStringsDiff.deleted.length
            # General case of _qsByRequester[computation._id]
            # being unchanged after remerging
            return

        requestsChanged = false

        for addedQss in qsStringsDiff.added
            if addedQss not of @_requestersByQs
                @_requestersByQs[addedQss] = {}
                requestsChanged = true
            @_requestersByQs[addedQss][computation._id] = computation

        for deletedQss in qsStringsDiff.deleted
            delete @_requestersByQs[deletedQss][computation._id]
            if _.isEmpty @_requestersByQs[deletedQss]
                delete @_requestersByQs[deletedQss]
                requestsChanged = true

        if requestsChanged and not @_requestsChanged
            @_requestsChanged = true
            Tracker.afterFlush (=> @remergeQueries()), Number.POSITIVE_INFINITY


    _deleteComputationQsRequests: (computation) ->
        # Note:
        # AutoVar handles logic to call @_deleteComputationQsRequests
        # because it involves complicated sequencing with React component
        # rendering.

        return if computation._id not of @_qsByRequester

        requestsChanged = false

        for deletedQss of @_qsByRequester[computation._id]
            delete @_requestersByQs[deletedQss][computation._id]
            if _.isEmpty @_requestersByQs[deletedQss]
                delete @_requestersByQs[deletedQss]
                requestsChanged = true

        delete @_qsByRequester[computation._id]

        if requestsChanged and not @_requestsChanged
            @_requestsChanged = true
            Tracker.afterFlush (=> @remergeQueries()), Number.POSITIVE_INFINITY


    _getCanonicalSelector: (selector) ->
        # 1. selector:"x" turns into selector:_id:"x"
        # 2. f:$in:["singleton"] becomes f:"singleton"
        # 3. Order keys in parts like $in

        if _.isString selector
            return _id: selector
        else if selector is undefined or _.isEmpty selector
            return undefined

        getTransformed = (subSel, levelIsSpecial) =>
            # levelIsSpecial:
            #   E.g. the top-level and a level after $in are special
            #   and can be reordered, but values to match which happen
            #   to be objects or arrays are non-special
            # 1. Sort objects and arrays if levelIsSpecial
            # 2. Transform singleton $in, $and and $or expressions into non-arrays

            if _.isArray subSel
                ret = []
                for v in subSel
                    ret.push getTransformed(
                        v
                        J.util.isPlainObject(v) and _.any(
                            subSelKey[0] is '$' for subSelKey of v
                        )
                    )
                if levelIsSpecial
                    J.util.sortByKey(
                        ret
                        if _.any(_.isArray(x) or J.util.isPlainObject(x) for x in ret)
                            EJSON.stringify
                        else
                            _.identity
                        transform: false
                    )
                ret

            else if J.util.isPlainObject subSel
                keys = _.keys subSel
                if levelIsSpecial then keys.sort()
                ret = {}
                for k in keys
                    ret[k] = getTransformed(
                        subSel[k]
                        _.any [
                            k[0] is '$' and k not in ['$eq', '$gt', '$gte', '$lt', '$lte']
                        ,
                            J.util.isPlainObject(subSel[k]) and _.any(
                                subSelKey[0] is '$' for subSelKey of subSel[k]
                            )
                        ]
                    )
                    if J.util.isPlainObject(ret[k])
                        for operator in ['$in', '$and', '$or']
                            if ret[k][operator]?.length is 1
                                ret[k] = ret[k][operator][0]
                                break
                ret

            else
                subSel

        getTransformed selector, true


    _getCanonicalProjection: (modelClass, projection) ->
        return undefined if projection is undefined or _.isEmpty projection

        inclusionSet = @_projectionToInclusionSet modelClass, projection

        # Handle cases like {'a.x':true, 'a.x.y.z':true} -> {'a.x': true}
        if not _.isEmpty(inclusionSet) then while true
            mergedSomething = false
            includeSpecs = _.keys inclusionSet
            for i in [0...includeSpecs.length - 1]
                iSpec = includeSpecs[i]
                iSpecParts = iSpec.split('.')
                for j in [i + 1...includeSpecs.length]
                    jSpec = includeSpecs[j]
                    jSpecParts = jSpec.split('.')

                    shortSpecParts = null
                    longSpec = null
                    longSpecParts = null
                    if iSpecParts.length < jSpecParts.length
                        shortSpecParts = iSpecParts
                        longSpec = jSpec
                        longSpecParts = jSpecParts
                    else if jSpecParts.length < iSpecParts.length
                        shortSpecParts = jSpecParts
                        longSpec = iSpec
                        longSpecParts = iSpecParts
                    continue if not longSpec?

                    if EJSON.equals shortSpecParts, longSpecParts[0...shortSpecParts.length]
                        delete inclusionSet[longSpec]
                        mergedSomething = true
                        break

                break if mergedSomething
            break if not mergedSomething

        defaultIncludeSpecSet = {}
        for fieldName, fieldSpec of modelClass.fieldSpecs
            if (fieldSpec.include ? true)
                defaultIncludeSpecSet[fieldName] = true
        for reactiveName, reactiveSpec of modelClass.reactiveSpecs
            if (reactiveSpec.include ? false)
                defaultIncludeSpecSet[reactiveName] = true

        includesAllDefaults = _.all (
            inclusionSet[includeSpec] for includeSpec of defaultIncludeSpecSet
        )

        canonicalProjection = {}
        if not includesAllDefaults
            canonicalProjection._ = false
        for includeSpec of inclusionSet
            unless includesAllDefaults and includeSpec of defaultIncludeSpecSet
                canonicalProjection[includeSpec] = true

        return undefined if _.isEmpty canonicalProjection

        sortedCanonicalProjection = {}
        for projectionKey in _.keys(canonicalProjection).sort()
            sortedCanonicalProjection[projectionKey] = canonicalProjection[projectionKey]
        sortedCanonicalProjection


    _projectionToInclusionSet: (modelClass, projection) ->
        # See the projection semantics documentation at the top of this file.
        # Returns {includeSpec: true}

        if projection is undefined then projection = {}
        inclusionSet = {}

        if projection._ is false
            for includeSpec, include of projection
                continue if includeSpec is '_'
                if include then inclusionSet[includeSpec] = true

        else
            for fieldName, fieldSpec of modelClass.fieldSpecs
                if fieldSpec.include ? true
                    inclusionSet[fieldName] = true

            for reactiveName, reactiveSpec of modelClass.reactiveSpecs
                if reactiveSpec.include ? false
                    inclusionSet[reactiveName] = true

            for includeSpec, include of projection
                continue if includeSpec is '_'
                if include
                    inclusionSet[includeSpec] = true
                else
                    delete inclusionSet[includeSpec]

        inclusionSet


    _qsToMongoOptions: (qs) ->
        modelClass = J.models[qs.modelName]
        options = {}
        options.fields = @projectionToMongoFieldsArg modelClass, qs.fields ? {}
        if _.isEmpty options.fields then delete options.fields
        options.sort = @sortSpecToMongoSortSpec modelClass, qs.sort ? {}
        if _.isEmpty options.sort then delete options.sort
        if qs.limit? then options.limit = J.util.deepClone qs.limit
        if qs.skip? then options.skip = J.util.deepClone qs.skip
        options


    checkQuerySpec: (querySpec) ->
        # Throws an error if the querySpec is invalid

        modelClass = J.models[querySpec.modelName]
        inclusionSet = @_projectionToInclusionSet modelClass, querySpec.fields ? {}

        if J.util.isPlainObject(querySpec.selector) then for sKey, sValue of querySpec.selector
            if sKey isnt '_id' and sKey[0] isnt '$'
                ok = false
                for fKey, fValue of inclusionSet
                    if fKey.split('.')[0] is sKey.split('.')[0]
                        ok = true
                        break
                if not ok
                    throw new Error "
                        Missing projection for selector key #{JSON.stringify sKey}.
                        The projection must include/exclude every key in the selector
                        so that the fetch also works as expected on the client."

        if querySpec.sort? then for sKey, sValue of querySpec.sort
            if sKey isnt '_id' and sKey[0] isnt '$'
                ok = false
                for fKey, fValue of inclusionSet
                    if fKey.split('.')[0] is sKey.split('.')[0]
                        ok = true
                        break
                if not ok
                    throw new Error "
                        Missing projection for sort key #{JSON.stringify sKey}.
                        The projection must include/exclude every key in the sort
                        so that the fetch also works as expected on the client."


    getMerged: (querySpecs) ->
        # Attempt to pairwise merge all the querySpecs.

        querySpecsByModel = {} # modelName: [querySpecs] (will be pairwise merged)
        mergedQuerySpecs = []

        querySpecs = (@makeCanonicalQs qs for qs in querySpecs)

        for qs in querySpecs
            querySpecsByModel[qs.modelName] ?= []
            querySpecsByModel[qs.modelName].push qs

        for modelName, querySpecs of querySpecsByModel
            qsStringSet = {} # qsString: true
            for qs in querySpecs
                qsStringSet[@stringifyQs qs] = true

            # Iterate until no pair of qsStrings in qsStringSet
            # can be pairwise merged.
            while true
                mergedSomething = false

                qsStrings = _.keys qsStringSet
                for qsString, i in qsStrings[...qsStrings.length - 1]
                    querySpec = @parseQs qsString
                    for qss in qsStrings[i + 1...]
                        qs = @parseQs qss
                        pairwiseMergedQs = @tryQsPairwiseMerge querySpec, qs
                        if pairwiseMergedQs?
                            pairwiseMergedQsString = @stringifyQs pairwiseMergedQs
                            delete qsStringSet[qsString]
                            delete qsStringSet[qss]
                            qsStringSet[pairwiseMergedQsString] = true
                            mergedSomething = true
                            break

                    break if mergedSomething

                break if not mergedSomething

            # Dump qsStringSet into mergedQuerySpecs
            for qsString of qsStringSet
                mergedQuerySpecs.push @parseQs qsString

        mergedQuerySpecs


    isQueryReady: (qs) ->
        # A query is considered ready if:
        # (1) It was bundled into the set of merged queries that the server
        #     has come back and said are ready.
        # (2) It has an _id selector, and all of the first-level doc values
        #     in its projection aren't undefined.
        #     (Note that we can't infer anything about first-level objects
        #     in the doc, because they may or may not be partial subdocs.)

        qs = @makeCanonicalQs qs
        qsString = @stringifyQs qs
        modelClass = J.models[qs.modelName]

        testId = (instanceId) =>
            return false if instanceId not of modelClass.collection._attachedInstances

            options = @_qsToMongoOptions(qs)
            options.transform = false
            options.reactive = false
            doc = modelClass.findOne(instanceId, options)
            return false if not doc?

            for fieldSpec of options.fields ? {}
                fieldSpecParts = fieldSpec.split('.')
                if fieldSpecParts[0] is '_id'
                    continue
                else if fieldSpecParts[0] is '_reactives'
                    reactiveName = fieldSpecParts[1]?
                    value = doc._reactives?[reactiveName]?.val
                else
                    fieldName = fieldSpecParts[0]
                    value = doc[fieldName]

                return false if value is undefined

                # This value might be ready, but there's a risk that
                # it's actually a partial subdoc, so we can only
                # trust it after qsString appears in @_unmergedQsSet.
                # FIXME:
                # It's possible to do smarter bookkeeping to return true
                # when the full (sub)object being requested is already
                # on the client.
                return false if J.util.isPlainObject value

            true

        helper = =>
            return true if qsString of @_unmergedQsSet and qsString of @_nextUnmergedQsSet

            # For queries with an _id filter, say it's ready as long as minimongo
            # has an attached entry with that _id and no other parts of the selector
            # rule out that one doc.
            if _.isString(qs.selector?._id) and testId(qs.selector._id)
                return true
            else if _.isArray(qs.selector?._id?.$in) and _.all(testId(id) for id in qs.selector._id.$in)
                return true

            false

        ret = helper()
        # console.debug 'isQueryReady', ret, qsString
        ret


    isQsCovered: (qs, superQs) ->
        # Returns whether the results from the querySpecs in superQsArr
        # are sufficient to provide accurate results to qs

        qs = @makeCanonicalQs qs
        superQs = @makeCanonicalQs superQs

        return false if qs.modelName isnt superQs.modelName
        modelClass = J.models[qs.modelName]

        # Make sure the selector is covered
        return false if not @isSelectorCovered qs, superQs

        # And make sure the projection is covered
        inclusionSet = @_projectionToInclusionSet modelClass, qs.fields
        superInclusionSet = @_projectionToInclusionSet modelClass, superQs.fields
        inclusionDiff = J.util.diffStrings _.keys(inclusionSet), _.keys(superInclusionSet)
        for missingInclusionSpec in inclusionDiff.deleted
            # Check for a situation like "w.x.y.z" being covered by "w.x"
            ok = false
            missingInclusionSpecParts = missingInclusionSpec.split('.')
            for i in [0...missingInclusionSpecParts.length - 1]
                if missingInclusionSpecParts[0..i].join('.') of superInclusionSet
                    ok = true
                    break
            return false if not ok

        true


    isSelectorCovered: (qs, superQs) ->
        # Returns true if (modelName, selector, sort, limit, skip)
        # cause superQs to have a superset of the returned _ids
        # that qs has, ignoring qs.fields and superQs.fields

        qs = @makeCanonicalQs qs
        delete qs.fields
        superQs = @makeCanonicalQs superQs
        delete superQs.fields

        return true if EJSON.equals qs, superQs
        return false if qs.modelName isnt superQs.modelName

        isValueSpecCovered = (valueSpec, superValueSpec) ->
            possibleValues = [valueSpec]
            if J.util.isPlainObject(valueSpec) and _.keys(valueSpec).length is 1 and valueSpec.$in?
                possibleValues = valueSpec.$in
            superPossibleValues = [superValueSpec]
            if J.util.isPlainObject(superValueSpec) and _.keys(superValueSpec).length is 1 and superValueSpec.$in?
                superPossibleValues = superValueSpec.$in

            for possibleValue in possibleValues
                return false if not _.any(
                    EJSON.equals possibleValue, v for v in superPossibleValues
                )
            true

        # Return false if superQs.selector might filter too much
        for superSelectorKey, superSelectorValue of superQs.selector ? {}
            return false unless qs.selector? and superSelectorKey of qs.selector and isValueSpecCovered(
                qs.selector[superSelectorKey], superSelectorValue
            )

        if qs.skip? or superQs.skip?
            # Can't handle skip yet
            return false

        if superQs.limit?
            # If superQs has a limit, then qs has to be identical
            # except with a possibly smaller limit
            if qs.limit? and qs.limit <= superQs.limit
                dummyQs = _.clone qs
                dummyQs.limit = superQs.limit
                return EJSON.equals dummyQs, superQs
            else
                return false

        true


    makeCanonicalQs: (qs) ->
        # Returns an equivalent querySpec but in "canonical form"
        # so two querySpecs written with minor differences can
        # be fingerprinted by their @stringifyQs value

        qs = _.clone qs

        qs.selector = @_getCanonicalSelector qs.selector

        qs.fields = @_getCanonicalProjection J.models[qs.modelName], qs.fields

        if qs.sort is undefined or _.isEmpty qs.sort
            qs.sort = undefined

        if qs.limit is 0 or not qs.limit?
            qs.limit = undefined

        if qs.skip is 0 or not qs.skip?
            qs.skip = undefined

        # This establishes the canonical order of the QS fields
        J.util.withoutUndefined
            modelName: qs.modelName
            selector: qs.selector
            fields: qs.fields
            sort: qs.sort
            limit: qs.limit
            skip: qs.skip


    parseQs: (qsString) ->
        EJSON.parse qsString


    projectionToMongoFieldsArg: (modelClass, projection) ->
        # Input:
        #     The kind of projection passed to the "fields" argument when calling .fetch
        #     on a Model in JFramework.
        # Output:
        #     The corresponding Mongo-style fields-argument that we can pass to
        #     the second argument of MongoCollection.find.

        inclusionSet = @_projectionToInclusionSet modelClass, projection

        mongoFieldsArg = {}

        for includeSpec of inclusionSet
            includeSpecParts = includeSpec.split('.')
            fieldOrReactiveName = includeSpecParts[0]

            if not (
                fieldOrReactiveName of modelClass.fieldSpecs or
                fieldOrReactiveName of modelClass.reactiveSpecs
            )
                throw new Error "Invalid fieldOrReactiveName in
                    #{modelClass.name} inclusion set: #{includeSpec}"

            if fieldOrReactiveName of modelClass.reactiveSpecs
                # Convert someReactiveName.[etc] to _reactives.#{reactiveName}.val.[etc]
                reactiveValSpec =
                    ["_reactives.#{fieldOrReactiveName}.val"].concat(includeSpecParts[1...]).join('.')
                mongoFieldsArg[reactiveValSpec] = 1
                reactiveTsSpec = "_reactives.#{fieldOrReactiveName}.ts"
                mongoFieldsArg[reactiveTsSpec] = 1
                reactiveDirtySpec = "_reactives.#{fieldOrReactiveName}.dirty"
                mongoFieldsArg[reactiveDirtySpec] = 1
            else
                mongoFieldsArg[includeSpec] = 1

        if _.isEmpty mongoFieldsArg
            mongoFieldsArg._id = 1

        mongoFieldsArg


    remergeQueries: ->
        return if @_requestInProgress or not @_requestsChanged
        @_requestsChanged = false

        newUnmergedQsStrings = _.keys @_requestersByQs
        newUnmergedQuerySpecs = (@parseQs qsString for qsString in newUnmergedQsStrings)
        @_nextUnmergedQsSet = {}
        @_nextUnmergedQsSet[qsString] = true for qsString in newUnmergedQsStrings
        unmergedQsStringsDiff = J.util.diffStrings _.keys(@_unmergedQsSet), _.keys(@_nextUnmergedQsSet)

        newMergedQuerySpecs = @getMerged newUnmergedQuerySpecs
        newMergedQsStrings = (@stringifyQs querySpec for querySpec in newMergedQuerySpecs)
        @_nextMergedQsSet = {}
        @_nextMergedQsSet[qsString] = true for qsString in newMergedQsStrings
        mergedQsStringsDiff = J.util.diffStrings _.keys(@_mergedQsSet), _.keys(@_nextMergedQsSet)

        addedQuerySpecs = (@parseQs qsString for qsString in mergedQsStringsDiff.added)
        deletedQuerySpecs = (@parseQs qsString for qsString in mergedQsStringsDiff.deleted)

        doAfterUpdatingUnmergedQsSet = =>
            for addedUnmergedQsString in unmergedQsStringsDiff.added
                for computationId in _.keys @_requestersByQs[addedUnmergedQsString] ? {}
                    @_requestersByQs[addedUnmergedQsString][computationId].invalidate()

            # There may be changes to @_requestersByQs that we couldn't act on
            # until this request was done.
            Tracker.afterFlush (=> @remergeQueries()), Number.POSITIVE_INFINITY

        if not (addedQuerySpecs.length or deletedQuerySpecs.length)
            # The merged query set hasn't changed so we don't need to hit the server,
            # but it's important to update @_unmergedQsSet as if we had.
            @_unmergedQsSet = _.clone @_nextUnmergedQsSet
            doAfterUpdatingUnmergedQsSet()
            return


        debug = true
        if debug
            consolify = (querySpec) =>
                obj = _.clone querySpec
                for x in ['selector', 'fields', 'sort']
                    if x of obj then obj[x] = J.util.stringify obj[x]
                obj

            if deletedQuerySpecs.length
                console.groupCollapsed "-"
                console.debug "    ", consolify(qs) for qs in deletedQuerySpecs
                console.groupEnd()
            if addedQuerySpecs.length
                console.groupCollapsed "+"
                for qsString in unmergedQsStringsDiff.added
                    for computationId, computation of @_requestersByQs[qsString]
                        if false then console.log computation
                console.debug "    ", consolify(qs) for qs in addedQuerySpecs
                console.groupEnd()

        @_requestInProgress = true
        Meteor.call '_updateDataQueries',
            @SESSION_ID,
            addedQuerySpecs,
            deletedQuerySpecs,
            (error, result) =>
                @_requestInProgress = false
                if error
                    console.error "Fetching error:", error
                    return

                @_unmergedQsSet = _.clone @_nextUnmergedQsSet
                @_mergedQsSet = _.clone @_nextMergedQsSet

                doAfterUpdatingUnmergedQsSet()


    requestQuery: (querySpec) ->
        J.assert Tracker.active
        @checkQuerySpec querySpec

        computation = Tracker.currentComputation
        @_addComputationQsRequest computation, querySpec

        if @isQueryReady querySpec
            modelClass = J.models[querySpec.modelName]
            mongoSelector = @selectorToMongoSelector modelClass, querySpec.selector
            options = @_qsToMongoOptions querySpec

            if Tracker.active
                options.reactive = false
                results = J.List modelClass.find(mongoSelector, options).fetch()

                # The individual model instances' getters have their own reactivity, so
                # this query should only invalidate if a result gets added/removed/moved.
                idQueryOptions = _.clone options
                idQueryOptions.fields = _id: 1
                idQueryOptions.reactive = true
                idQueryOptions.transform = false

                initializing = true
                invalidator = -> computation.invalidate() if not initializing
                modelClass.find(mongoSelector, idQueryOptions).observe
                    added: invalidator
                    movedTo: invalidator
                    removed: invalidator
                initializing = false

                results

            else
                J.List modelClass.find(querySpec.selector, options).fetch()

        else
            throw J.makeValueNotReadyObject()


    selectorToMongoSelector: (modelClass, selector) ->
        # Input:
        #     The kind of selector passed to the first argument of .fetch
        #     on a Model in JFramework
        # Output:
        #     The corresponding Mongo-style selector that we can pass to
        #     MongoCollection.find

        if not J.util.isPlainObject selector
            return selector

        mongoSelector = {}
        for selectorKey, selectorValue of selector
            selectorKeyParts = selectorKey.split('.')
            fieldOrReactiveName = selectorKeyParts[0]

            if fieldOrReactiveName is '_id'
                mongoSelector[selectorKey] = selectorValue

            else if fieldOrReactiveName of modelClass.fieldSpecs
                mongoSelector[selectorKey] = selectorValue

            else if fieldOrReactiveName of modelClass.reactiveSpecs
                reactiveSpec = modelClass.reactiveSpecs[fieldOrReactiveName]
                if not reactiveSpec.selectable
                    throw new Error "Can't fetch with a selector on a non-selectable
                        reactive: #{modelClass.name}.#{fieldOrReactiveName}"
                reactiveSelectorKey = ["_reactives.#{fieldOrReactiveName}.val"].concat(
                    selectorKeyParts[1...]
                ).join('.')
                mongoSelector[reactiveSelectorKey] = selectorValue

            else
                throw new Error "#{modelClass} fetch selector contains invalid
                    selectorKey: #{selectorKey}"

        mongoSelector


    sortSpecToMongoSortSpec: (modelClass, sortSpec) ->
        mongoSortSpec = {}
        for sortKey, direction of sortSpec
            sortKeyParts = sortKey.split('.')
            fieldOrReactiveName = sortKeyParts[0]

            if fieldOrReactiveName is '_id'
                mongoSortSpec[sortKey] = direction

            else if fieldOrReactiveName of modelClass.fieldSpecs
                mongoSortSpec[sortKey] = direction

            else if fieldOrReactiveName of modelClass.reactiveSpecs
                reactiveSpec = modelClass.reactiveSpecs[fieldOrReactiveName]
                if not reactiveSpec.selectable
                    throw new Error "Can't sort on a non-selectable reactive:
                        #{modelClass.name}.#{fieldOrReactiveName}.val"
                reactiveSortKey = ["_reactives.#{fieldOrReactiveName}.val"].concat(
                    sortKeyParts[1...]
                ).join('.')
                mongoSortSpec[reactiveSortKey] = direction

            else
                throw new Error "#{modelClass} fetch sort spec contains invalid
                    key: #{sortKey}"

        mongoSortSpec


    stringifyQs: (qs) ->
        EJSON.stringify @makeCanonicalQs qs


    tryQsPairwiseMerge: (a, b) ->
        # Return a new querySpec that covers both a and b, or null
        # if pairwise merging failed.
        #
        # Strategy:
        # 1. If one qs covers the other, return the superQs.
        # 2. If everything is identical except the value of a single
        #    selectorKey, return a new qs with a merged selectorKey.
        # 3. If everything is identical except the projection,
        #    return a new qs with a merged projection.

        a = @makeCanonicalQs a
        b = @makeCanonicalQs b
        return null if a.modelName isnt b.modelName
        modelClass = J.models[a.modelName]

        # 1.
        return b if @isQsCovered a, b
        return a if @isQsCovered b, a

        # 2.
        #    a and b must have the exact same selectorKeys except
        #    the value differs at one point
        tryMergingSelectors = =>
            return null unless a.selector? and b.selector?
            aSelectorKeys = _.keys a.selector
            bSelectorKeys = _.keys b.selector
            return null if not EJSON.equals aSelectorKeys, bSelectorKeys

            diffKeys = []
            for selectorKey of a.selector
                if not EJSON.equals a.selector[selectorKey], b.selector[selectorKey]
                    diffKeys.push selectorKey
            return null unless diffKeys.length is 1
            diffKey = diffKeys[0]

            getPossibleValues = (selectorValue) =>
                if J.util.isPlainObject selectorValue
                    if _.size(selectorValue) is 1 and selectorValue.$in?
                        selectorValue.$in
                    else if _.any(k[0] is '$' for k of selectorValue)
                        null
                    else
                        [selectorValue]
                else
                    [selectorValue]

            aSelectorValues = getPossibleValues a.selector[diffKey]
            bSelectorValues = getPossibleValues b.selector[diffKey]
            return null unless aSelectorValues? and bSelectorValues?

            selectorValuesSet = {} # stringifiedValue: true
            for aValue in aSelectorValues
                selectorValuesSet[EJSON.stringify aValue] = true
            for bValue in bSelectorValues
                selectorValuesSet[EJSON.stringify bValue] = true
            mergedSelectorValues = (EJSON.parse x for x of selectorValuesSet)

            mergedSelector = _.clone a.selector
            mergedSelector[diffKey] = $in: mergedSelectorValues
            mergedQs = _.clone a
            mergedQs.selector = @_getCanonicalSelector mergedSelector
            mergedQs

        selectorMergedQs = tryMergingSelectors()
        if selectorMergedQs? and @isQsCovered(a, selectorMergedQs) and @isQsCovered(b, selectorMergedQs)
            return selectorMergedQs

        # 3.
        tryMergingProjections = =>
            aDummy = _.clone a
            delete aDummy.fields
            bDummy = _.clone b
            delete bDummy.fields
            return null unless EJSON.equals aDummy, bDummy

            aInclusionSet = @_projectionToInclusionSet modelClass, a.fields
            bInclusionSet = @_projectionToInclusionSet modelClass, b.fields
            mergedInclusionSet = _.extend(
                _.clone aInclusionSet
                bInclusionSet
            )

            mergedQs = _.clone a
            mergedQs.fields = @_getCanonicalProjection modelClass, _.extend(
                _: false
                mergedInclusionSet
            )
            mergedQs

        projectionMergedQs = tryMergingProjections()
        if projectionMergedQs?
            return projectionMergedQs

        null
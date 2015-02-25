class J.AutoVar extends Tracker.Computation
    constructor: (tag, valueFunc, onChange, options) ->
        ###
            AutoVars default to being "lazy", i.e. not calculated
            until .get().

            onChange:
                A function to call with (oldValue, newValue) when
                the value changes.
                May also pass onChange=true or null.
                If onChange is either a function or true, the
                AutoVar becomes non-lazy.

            options:
                creator: Set a different creator computation.
                wrap: Same as Var.wrap
        ###

        unless @ instanceof J.AutoVar
            return new J.AutoVar tag, valueFunc, onChange, options

        if _.isFunction tag
            # Alternate signature: J.AutoVar(valueFunc, onChange, options)
            options = onChange
            onChange = valueFunc
            valueFunc = tag
            tag = undefined

        unless _.isFunction(valueFunc)
            throw new Meteor.Error "AutoVar must be constructed with valueFunc"

        unless not onChange? or _.isFunction(onChange) or onChange is true
            throw new Meteor.Error "AutoVar onChange must be either null or a function
                or true (true simply forces non-lazy first evaluation): #{onChange}"

        @_id = J.getNextId()
        if J.debugGraph then J.graph[@_id] = @

        @tag = if J.debugTags then J.util.stringifyTag(tag) else null

        @valueFunc = valueFunc
        if Meteor.isServer
            @_func = Meteor.bindEnvironment @_runValueFunc.bind @
        else
            @_func = @_runValueFunc.bind @

        @onChange = onChange ? null
        if options?.creator is undefined
            @creator = Tracker.currentComputation
        else
            @creator = options.creator
        @wrap = options?.wrap ? true
        @sortKey = options?.sortKey ? 0.3
        @component = options?.component

        @invalidated = false
        @_invalidAncestors = [] # autoVars
        @_onInvalidateCallbacks = []
        @stopped = false

        @_getters = [] # computations
        @_sideGetters = [] # computations
        @_children = [] # computations
        @creator?._children.push @

        @_getting = false
        @_previousReadyValue = undefined
        @_value = undefined

        if @onChange
            # Truthy onChange means do a non-lazy first run
            # of valueFunc.
            Tracker.afterFlush =>
                if @_value is undefined then @invalidate()


    _addGetter: (getter) ->
        if getter not in @_getters
            @_getters.push getter
            getter.onInvalidate =>
                @_getters.splice @_getters.indexOf(getter), 1


    _addSideGetter: (getter) ->
        if getter not in @_sideGetters
            @_sideGetters.push getter
            getter.onInvalidate =>
                @_sideGetters.splice @_sideGetters.indexOf(getter), 1


    _addInvalidAncestor: (autoVar) ->
        @_invalidAncestors.push autoVar
        for comp in @_getters
            comp._addInvalidAncestor? autoVar


    _hasInvalidComponentAncestor: ->
        if @component?._hasInvalidAncestor() then true
        else @creator?._hasInvalidComponentAncestor?() ? false


    _removeInvalidAncestor: (autoVar) ->
        i = @_invalidAncestors.indexOf autoVar
        if i >= 0 then @_invalidAncestors.splice i, 1
        for comp in @_getters
            comp._removeInvalidAncestor? autoVar


    _runValueFunc: ->
        @onInvalidate =>
            sg.invalidate() for sg in _.clone @_sideGetters
            c.stop() for c in _.clone @_children

            if not @stopped
                @_invalidAncestors = []
                @_addInvalidAncestor @

        if @ isnt @component?._elementVar and Tracker.nonreactive(=> @_hasInvalidComponentAncestor())
            @_hasInvalidComponentAncestor() # we want to recompute when it's false
            value = J.makeValueNotReadyObject()
        else
            if @ isnt @component?._elementVar
                if Meteor.isClient then J.fetching._deleteComputationQsRequests @

            try
                # ValueFunc may either return or throw J.Var.NOT_READY.
                # It may not return undefined.
                value = @valueFunc.call null, @

            catch e
                if e instanceof J.VALUE_NOT_READY
                    value = e
                else
                    console.log e.stack
                    throw e

        if value is undefined
            throw new Meteor.Error "#{@toString()}.valueFunc must not return undefined."

        @_removeInvalidAncestor @

        # It's kosher for a valueFunc to call stop() on its own AutoVar.
        if not @stopped then @_set value


    _set: (value) ->
        previousValue = @_value
        newValue = @_value = J.Var::maybeWrap.call @, value, true

        if _.isFunction(@onChange) and previousValue not instanceof J.VALUE_NOT_READY
            @_previousReadyValue = previousValue

        if newValue isnt previousValue
            getter.invalidate() for getter in _.clone @_getters

        if (
            _.isFunction(@onChange) and
            @_value not instanceof J.VALUE_NOT_READY and
            @_value isnt @_previousReadyValue
        )
            previousReadyValue = @_previousReadyValue
            @_previousReadyValue = undefined # Free the memory
            Tracker.afterFlush =>
                if not @stopped
                    @onChange.call @, previousReadyValue, newValue


    debug: ->
        console.log @toString()


    get: ->
        if @stopped
            throw new Meteor.Error "#{Tracker.currentComputation?._id} can't get
                value of inactive AutoVar: #{@}"

        if @_getting
            msg = "AutoVar dependency cycle involving #{Tracker.currentComputation} and #{@}"
            console.error msg
            throw msg

        if Meteor.isServer and J._inMethod.get()
            # We're just using the Var to wrap the value, e.g.
            # array becomes J.List.
            return J.Var(@valueFunc.call null, @).get()

        getter = Tracker.currentComputation

        @_getting = true
        if @_value is undefined
            @_compute()
        else
            while @_invalidAncestors.length
                ancestor = @_invalidAncestors.shift()
                ancestor._compute()
        @_getting = false

        if getter?
            @_addGetter getter
            if (
                (@_value instanceof J.List or @_value instanceof J.Dict) and
                @_value.creator?
            )
                # Normally Lists and Dicts control their own reactivity when methods
                # are called on them. The exception is when they get stopped.
                @_value.creator._addSideGetter getter

        if @_value instanceof J.VALUE_NOT_READY
            throw @_value if getter
            undefined
        else
            @_value


    set: ->
        throw new Meteor.Error "There is no AutoVar.set"


    stop: ->
        if @ isnt @component?._elementVar
            if Meteor.isClient then J.fetching._deleteComputationQsRequests @
        @_removeInvalidAncestor @
        @_invalidAncestors = []
        @creator?._children.splice @creator._children.indexOf(@), 1
        super


    toString: ->
        s = "AutoVar[#{J.util.stringifyTag @tag ? ''}##{@_id}]=#{J.util.stringify @_value}"
        if @stopped then s += " (stopped)"
        s
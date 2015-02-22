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

        @tag = if J.debugTags then tag else null

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

        @sortKey = 0.3
        @invalidated = false
        @_invalidAncestors = [] # autoVars
        @_onInvalidateCallbacks = []
        @stopped = false

        @creator?.onInvalidate =>
            @stop()

        @_getters = [] # computations
        @_getting = false
        @_previousReadyValue = undefined
        @_value = undefined

        if @onChange
            # Truthy onChange means do a non-lazy first run
            # of valueFunc.
            Tracker.afterFlush =>
                if @_value is undefined then @invalidate()


    _addInvalidAncestor: (autoVar) ->
        @_invalidAncestors.push autoVar
        for comp in @_getters
            comp._addInvalidAncestor? autoVar


    _removeInvalidAncestor: (autoVar) ->
        i = @_invalidAncestors.indexOf autoVar
        if i >= 0 then @_invalidAncestors.splice i, 1
        for comp in @_getters
            comp._removeInvalidAncestor? autoVar


    _runValueFunc: ->
        @onInvalidate =>
            @_invalidAncestors = []
            if not @stopped
                @_addInvalidAncestor @

        try
            # ValueFunc may either return or throw J.Var.NOT_READY.
            # It may not return undefined.
            value = @valueFunc.call null, @

        catch e
            if e instanceof J.VALUE_NOT_READY
                value = e
            else
                throw e

        if value is undefined
            throw new Meteor.Error "#{@toString()}.valueFunc must not return undefined."

        @_removeInvalidAncestor @

        # It's kosher for a valueFunc to call stop() on its own AutoVar.
        if not @stopped then @_set value


    _set: (value) ->
        previousValue = @_value
        @_value = J.Var::maybeWrap.call @, value

        if _.isFunction(@onChange) and previousValue not instanceof J.VALUE_NOT_READY
            @_previousReadyValue = previousValue

        if @_value isnt previousValue
            getter.invalidate() for getter in _.clone @_getters

        if (
            _.isFunction(@onChange) and
            @_value not instanceof J.VALUE_NOT_READY and
            @_value isnt @_previousReadyValue
        )
            # Need lexically scoped oldValue and newValue
            oldValue = @_previousReadyValue
            newValue = @_value
            Tracker.afterFlush =>
                if not @stopped
                    @onChange.call @, oldValue, newValue


    debug: ->
        console.log @toString()


    get: ->
        if @_getting
            console.error "AutoVar dependency cycle involving #{@toString()}"
            throw "AutoVar dependency cycle involving #{@toString()}"

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

        if getter? and getter not in @_getters
            @_getters.push getter
            getter.onInvalidate =>
                @_getters.splice @_getters.indexOf(getter), 1

        if @_value instanceof J.VALUE_NOT_READY
            throw @_value if getter
            undefined
        else
            @_value


    set: ->
        throw new Meteor.Error "There is no AutoVar.set"


    toString: ->
        s = "AutoVar[#{J.util.stringifyTag @tag ? ''}##{@_id}]=#{J.util.stringify @_value}"
        if @stopped then s += " (stopped)"
        s
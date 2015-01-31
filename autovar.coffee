class J.AutoVar
    constructor: (@valueFunc, @onChange = null, @equalsFunc = J.util.equals) ->
        unless _.isFunction(@valueFunc)
            throw new Meteor.Error "AutoVar must be constructed with valueFunc"

        @_var = new ReactiveVar undefined, @equalsFunc

        @active = true
        @_valuecomp = null
        @_setupValueComp()

    _recompute: ->
        oldValue = Tracker.nonreactive => @_var.get()
        newValue = @valueFunc.call null
        if newValue is undefined
            throw new Meteor.Error "AutoVar.valueFunc must not return undefined"

        @_var.set newValue
        unless @equalsFunc oldValue, newValue
            @onChange?.call null, oldValue, newValue

    _setupValueComp: ->
        @_valueComp?.stop()
        @_valueComp = Tracker.nonreactive => Tracker.autorun (c) =>
            @_recompute()

    get: ->
        unless @active
            throw new Meteor.Error "#{@constructor.name} is stopped"

        if @_valueComp.invalidated
            @_setupValueComp()

        @_var.get()

    replaceValueFunc: (@valueFunc) ->
        @_valueComp.invalidate()

    set: ->
        throw new Meteor.Error "There is no AutoVar.set"

    stop: ->
        if @active
            @_valueComp.stop()
            @active = false
            J.Dict._deepStop Tracker.nonreactive => @_var.get()
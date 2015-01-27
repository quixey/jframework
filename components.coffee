J.components = {}

# J.c et al store a reference to every mounted
# component for easy console debugging.
J.c = J._componentById = {} # componentId: component
J.cid = J._componentDomById = {} # componentId: componentDOMNode
J.cn = J._componentsByName = {} # componentName: {componentId: component}
J.cd = J._componentDomsByName = {} # componentName: {componentId: componentDOMNode}
nextComponentId = 0

# Queue up all component definitions to help the J
# framework startup sequence. E.g. all models
# must be defined before all components.
componentDefinitionQueue = []

J.dc = J.defineComponent = (componentName, componentSpec) ->
    componentDefinitionQueue.push
        name: componentName
        spec: componentSpec


class ReactiveDef
    constructor: (@params) ->

J.Reactive = (params) -> new ReactiveDef params

J._defineComponent = (componentName, componentSpec) ->
    for memberName in [
        'getDefaultProps'
        'getInitialState'
        'componentWillReceiveProps'
        'shouldComponentUpdate'
        'componentWillUpdate'
    ]
        if memberName of componentSpec
            throw "Unnecessary to define #{memberName} for J Framework components."


    reactSpec = _.clone componentSpec
    delete reactSpec.props
    delete reactSpec.state
    delete reactSpec.reactives

    reactSpec.displayName = componentName

    reactSpec.propTypes = {} # TODO


    # Make getter/setter fields for @state, e.g. @a gets/sets @state.a
    for stateFieldName, stateFieldSpec of componentSpec.state ? {}
        if stateFieldName of reactSpec
            throw "Name conflict between #{componentName}.#{stateFieldName} and
                #{componentName}.state.#{stateFieldName}"

        reactSpec[stateFieldName] = do (stateFieldName) -> (value) ->
            if arguments.length > 0 and value is undefined
                throw "Can't pass undefined to #{componentName}.#{stateFieldName}"
            else if value is undefined
                # Getter
                @state[stateFieldName].get()
            else
                # Setter
                stateFields = {}
                stateFields[stateFieldName] = value
                @set stateFields


    # Make reactive getters for @reactives, e.g. @a gets/sets @reactives.a
    for reactiveName, reactiveSpec of componentSpec.reactives ? {}
        if reactiveName of reactSpec
            throw "Name conflict between #{componentName}.#{reactiveName} and
                #{componentName}.reactives.#{reactiveName}"
        unless _.isFunction(reactiveSpec.val) or (
            # type is J.$instanceOf(J.AutoDict) and
            _.isFunction(reactiveSpec.keys) and
            _.isFunction(reactiveSpec.valForKey)
        )
            throw "#{componentName}.reactives.#{reactiveName} must have a val function"

        if reactiveSpec.valForKey? then reactSpec[reactiveName] =
            do (reactiveName, reactiveSpec) -> ->
                @reactives[reactiveName] ?= new J.AutoDict(
                    reactiveSpec.keys.bind @
                    reactiveSpec.valForKey.bind @
                    reactiveSpec.onChange ? null
                    reactiveSpec.same ? J.util.equals
                )

        else reactSpec[reactiveName] = do (reactiveName, reactiveSpec) -> ->
            equalsFunc = reactiveSpec.same ? J.util.equals

            updateReactiveVar = =>
                oldValue = Tracker.nonreactive => @reactives[reactiveName].get()
                newValue = reactiveSpec.val.apply @
                if newValue is undefined
                    throw "Can't return undefined from #{@}.reactives.#{reactiveName}.val"

                @reactives[reactiveName].set newValue

                if reactiveSpec.onChange? and not equalsFunc oldValue, newValue
                    reactiveSpec.onChange.call @, oldValue, newValue

            if @_reactiveComps[reactiveName]?.invalidated
                # Accessing an invalidated reactive before Meteor's flush has
                # time to recompute it. We'll effectively move it to the front
                # of the flush queue so it never returns an invalidated value.
                @_reactiveComps[reactiveName].stop()
                @_reactiveComps[reactiveName] = Tracker.nonreactive =>
                    Tracker.autorun (c) => updateReactiveVar()
            else
                valuePeek = Tracker.nonreactive => @reactives[reactiveName].get()
                if valuePeek is undefined
                    J.assert reactiveName not of @_reactiveComps
                    @_reactiveComps[reactiveName] = Tracker.nonreactive =>
                        Tracker.autorun (c) => updateReactiveVar()

            @reactives[reactiveName].get()


    reactSpec.getDefaultProps = ->
        defaultProps = {}
        for propName, propSpec of componentSpec.props
            if 'default' of propSpec
                defaultProps[propName] = propSpec.default
        defaultProps


    reactSpec.getInitialState = ->
        @_componentId = nextComponentId
        nextComponentId += 1
        J._componentById[@_componentId] = @
        J._componentsByName[componentName] ?= {}
        J._componentsByName[componentName][@_componentId] = @

        # Check for invalid prop names in @props
        validPropNamesSet = J.util.makeDictSet _.keys (componentSpec.props ? {})
        validPropNamesSet.className = true
        validPropNamesSet.children = true
        for propName, value of @props
            unless propName of validPropNamesSet
                throw "#{componentName} has no prop #{JSON.stringify propName}.
                    Only has #{JSON.stringify _.keys validPropNamesSet}."

        # Set up @prop
        @_props = {} # ReactiveVars for the props
        @prop = {} # Reactive getters for the props
        propSpecs = _.clone componentSpec.props ? {}
        propSpecs.className =
            type: React.PropTypes.string
        propSpecs.children =
            type: React.PropTypes.arrayOf React.PropTypes.element
        for propName, propSpec of propSpecs
            @_props[propName] = new ReactiveVar @props[propName],
                propSpec.same ? J.util.equals
            @prop[propName] = do (propName) => =>
                @_props[propName].get()

        # Set up @reactives
        @_reactiveComps = {} # nonDictReactiveName: computation
        @reactives = {} # reactiveName: reactiveVar|J.AutoDict
        for reactiveName, reactiveSpec of componentSpec.reactives ? {}
            if reactiveSpec.val?
                # AutoDicts get initialized later because they
                # immediately want to run their keyFunc.
                @reactives[reactiveName] = new ReactiveVar undefined,
                    reactiveSpec.same ? J.util.equals

        # Set up @state
        initialState = {}
        stateFromRoute =
            if J.Routable in (componentSpec.mixins ? []) and @stateFromRoute?
                @stateFromRoute @getParams(), @_cleanQueryFromRaw()
            else
                {}
        for stateFieldName, stateFieldSpec of componentSpec.state
            initialValue =
                if stateFromRoute[stateFieldName] isnt undefined
                    stateFromRoute[stateFieldName]
                else if _.isFunction stateFieldSpec.default
                    # TODO: If the type is J.$function then use the other if-branch
                    stateFieldSpec.default.apply @
                else
                    stateFieldSpec.default
            initialState[stateFieldName] = new ReactiveVar initialValue,
                stateFieldSpec.same ? J.util.equals

        initialState


    reactSpec.set = (stateFields, callback) ->
        if callback?
            @_setCallbacks ?= []
            @_setCallbacks.push callback

        for stateFieldName, value of stateFields
            unless stateFieldName of @state
                throw "#{componentName}.state.#{stateFieldName} does not exist."
            @state[stateFieldName].set value

        null


    reactSpec.componentWillReceiveProps = (nextProps) ->
        componentSpec.componentWillReceiveProps?.call @, nextProps

        for propName, newValue of nextProps
            propSpec =
                if propName in ['className', 'children']
                    {}
                else
                    componentSpec.props[propName]

            equalsFunc = propSpec.same ? J.util.equals
            oldValue = Tracker.nonreactive => @_props[propName].get()

            @_props[propName].set newValue

            unless equalsFunc oldValue, newValue
                propSpec.onChange?.call @, oldValue, newValue


    reactSpec.componentDidMount = ->
        J._componentDomById[@_componentId] = @getDOMNode()
        J._componentDomsByName[componentName] ?= {}
        J._componentDomsByName[componentName][@_componentId] = @getDOMNode()

        componentSpec.componentDidMount?.apply @


    reactSpec.shouldComponentUpdate = (nextProps, nextState) ->
        # We're counting on reactivity in the Meteor framework to
        # trigger forceUpdate().
        # Components can also manually call forceUpdate().
        false


    reactSpec.componentDidUpdate = (prevProps, prevState) ->
        componentSpec.componentDidUpdate?.call @, prevProps, prevState

        prevSetCallbacks = @_setCallbacks ? []
        delete @_setCallbacks
        callback() for callback in prevSetCallbacks


    reactSpec.componentWillUnmount = ->
        delete J._componentById[@_componentId]
        delete J._componentDomById[@_componentId]
        delete J._componentsByName[componentName][@_componentId]
        delete J._componentDomsByName[componentName][@_componentId]

        delete @_setCallbacks

        if @_renderComp?
            @_renderComp.stop()
            @_renderComp = null

        for reactiveName of @reactives
            if reactiveName of @_reactiveComps
                # It's a ReactiveVar
                @_reactiveComps[reactiveName].stop()
            else
                # It's an AutoDict
                @reactives[reactiveName].stop()
        @_reactiveComps = null
        @reactives = null

        componentSpec.componentWillUnmount?.apply @


    reactSpec.render = ->
        # Make sure we've run all the reactives' val-functions at least once.
        # Even if the render function never uses a reactive, that reactive
        # might need to monitor a value and do some side effect in its onChange.
        for reactiveName, reactiveSpec of componentSpec.reactives
            # We should be able to optimize this by only running
            # reactives with onChange functions, since val functions
            # aren't supposed to have side effects, but whatever.
            @[reactiveName]()

        renderedComponent = null
        if @_renderComp?
            # Application layer must have called @forceUpdate()
            @_renderComp.stop()
        @_renderComp = Tracker.autorun =>
            renderedComponent = componentSpec.render.apply @
        @_renderComp.onInvalidate (c) =>
            unless c.stopped
                @_renderComp.stop()
                @_renderComp = null
                Tracker.afterFlush => if @isMounted() then @forceUpdate()

        origClassName = renderedComponent.props.className
        renderedComponent.props.className = "#{componentName} #{@_componentId}"
        if origClassName?
            renderedComponent.props.className += " #{renderedComponent.props.className}"

        renderedComponent


    reactSpec.toString = ->
        "<#{componentName}-#{@_componentId}>"


    J.components[componentName] = React.createClass reactSpec


$$ = (elemType, props, children...) ->
    args = Array.prototype.slice.call arguments

    if typeof elemType[0] is 'string' and elemType[0].toUpperCase() is elemType[0]
        throw "No component class #{elemType}." unless elemType of J.components
        args[0] = J.components[elemType]

    React.createElement.apply React, args


Meteor.startup ->
    for componentDef in componentDefinitionQueue
        J._defineComponent componentDef.name, componentDef.spec

    componentDefinitionQueue = null
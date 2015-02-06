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

componentDebug = Meteor.settings.public?.debug?.jframework?.components ? false
_debugDepth = 0
_getDebugPrefix = (component = null, tabWidth = 4) ->
    numSpaces = Math.max 0, tabWidth * _debugDepth - 1
    "#{(' 'for i in [0...numSpaces]).join('')}#{if component? and _debugDepth is 0 then component.toString() else ''}"


J.dc = J.defineComponent = (componentName, componentSpec) ->
    componentDefinitionQueue.push
        name: componentName
        spec: componentSpec


J._defineComponent = (componentName, componentSpec) ->
    for memberName in [
        'getDefaultProps'
        'getInitialState'
        'componentWillReceiveProps'
        'shouldComponentUpdate'
        'componentWillUpdate'
    ]
        if memberName of componentSpec
            throw new Meteor.Error "Unnecessary to define #{memberName} for J Framework components
                (in #{componentName})"

    unless _.isFunction componentSpec.render
        throw new Meteor.Error "Missing #{componentName}.render method"

    reactSpec = _.clone componentSpec
    delete reactSpec.props
    delete reactSpec.state
    delete reactSpec.reactives

    reactSpec.displayName = componentName

    reactSpec.propTypes = {} # TODO


    # Make getter/setter fields for @state, e.g. @a gets/sets @state.a
    for stateFieldName, stateFieldSpec of componentSpec.state ? {}
        if stateFieldName of reactSpec
            throw new Meteor.Error "Name conflict between #{componentName}.#{stateFieldName} and
                #{componentName}.state.#{stateFieldName}"

        reactSpec[stateFieldName] = do (stateFieldName) -> (value) ->
            if arguments.length > 0 and value is undefined
                throw new Meteor.Error "Can't pass undefined to #{componentName}.#{stateFieldName}"
            else if value is undefined
                # Getter
                ret = @state[stateFieldName].get()
                if componentDebug then console.log _getDebugPrefix(@), "#{stateFieldName}()", ret
                ret
            else
                # Setter
                stateFields = {}
                stateFields[stateFieldName] = value
                @set stateFields


    # Make reactive getters for @reactives, e.g. @a gets/sets @reactives.a

    # For J.Routable components, make an automatic _route reactive
    reactiveSpecByName = _.clone componentSpec.reactives ? {}
    if J.Routable in (componentSpec.mixins ? [])
        reactiveSpecByName.route ?=
            type: J.$object
            val: ->
                params: {}
                query: {}

        pushNewRoute = (oldRouteSpec, newRouteSpec) ->
            currentRoutes = @getRoutes()
            lastRoute = currentRoutes[currentRoutes.length - 1]
            isLastRoute = lastRoute.handler.displayName is @constructor.displayName

            if isLastRoute and lastRoute.name?
                newPath = @makeGoodPath lastRoute.name, newRouteSpec.params().toObj(), newRouteSpec.query().toObj()
                if newPath isnt URI().resource()
                    # TODO: Block the re-rendering here; it's completely unnecessary.
                    # console.log 'PUSH', newPath
                    ReactRouter.HistoryLocation.push newPath

        origOnChange = reactiveSpecByName.route.onChange
        if origOnChange?
            reactiveSpecByName.route.onChange = (oldRouteSpec, newRouteSpec) ->
                origOnChange.call @, oldRouteSpec, newRouteSpec
                pushNewRoute.call @, oldRouteSpec, newRouteSpec
        else
            reactiveSpecByName.route.onChange = pushNewRoute

    for reactiveName, reactiveSpec of reactiveSpecByName
        if reactiveName of reactSpec
            throw new Meteor.Error "Name conflict between #{componentName}.#{reactiveName} and
                #{componentName}.reactives.#{reactiveName}"
        unless _.isFunction(reactiveSpec.val)
            throw new Meteor.Error "#{componentName}.reactives.#{reactiveName} must have a val function"

        reactSpec[reactiveName] = do (reactiveName) -> ->
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
        propSpecs = _.clone componentSpec.props ? {}
        propSpecs.className ?=
            type: React.PropTypes.string
        propSpecs.children ?=
            type: React.PropTypes.oneOfType [
                React.PropTypes.element
                React.PropTypes.arrayOf(React.PropTypes.element)
            ]
        for propName, value of @props
            unless propName of propSpecs
                throw new Meteor.Error "#{componentName} has no prop #{JSON.stringify propName}.
                    Only has #{JSON.stringify _.keys propSpecs}."
        # Set up @prop
        @_props = {} # ReactiveVars for the props
        @prop = {} # Reactive getters for the props
        for propName, propSpec of propSpecs
            @_props[propName] = new ReactiveVar @props[propName],
                propSpec.same ? J.util.equals
            @prop[propName] = do (propName) => =>
                ret = @_props[propName].get()
                if componentDebug then console.log _getDebugPrefix(@), "prop.#{propName}()", ret
                ret

        # Set up @reactives
        @reactives = {} # reactiveName: autoVar
        for reactiveName, reactiveSpec of reactiveSpecByName
            @reactives[reactiveName] = do (reactiveName, reactiveSpec) => J.AutoVar(
                =>
                    if componentDebug then console.log _getDebugPrefix(@), "!#{reactiveName}()"
                    _debugDepth += 1
                    ret = reactiveSpec.val.call @
                    if componentDebug then console.log _getDebugPrefix(), ret
                    _debugDepth -= 1
                    ret
                (
                    if reactiveSpec.onChange? then (oldValue, newValue) =>
                        J.assert not Tracker.active
                        if componentDebug
                            console.log "#{@toString()}.#{reactiveName}.onChange!"
                            console.log "    old:", oldValue
                            console.log "    new:", newValue
                        reactiveSpec.onChange.call @, oldValue, newValue
                    else null
                )
                reactiveSpec.same?.bind(@) ? J.util.equals
            )

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
                    if componentDebug then console.log _getDebugPrefix(@), "#{stateFieldName} !default()"
                    _debugDepth += 1
                    ret = stateFieldSpec.default.apply @
                    if componentDebug then console.log _getDebugPrefix(), ret
                    _debugDepth -= 1
                    ret
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
                throw new Meteor.Error "#{componentName}.state.#{stateFieldName} does not exist."
            @state[stateFieldName].set value

        null


    reactSpec.componentWillReceiveProps = (nextProps) ->
        componentSpec.componentWillReceiveProps?.call @, nextProps

        for propName, newValue of nextProps
            propSpec = componentSpec.props?[propName]
            unless propSpec?
                if propName is 'className'
                    propSpec = type: React.PropTypes.string
                else if propName is 'children'
                    propSpec = type: React.PropTypes.oneOfType [
                        React.PropTypes.element
                        React.PropTypes.arrayOf(React.PropTypes.element)
                    ]

            equalsFunc = propSpec.same ? J.util.equals
            oldValue = Tracker.nonreactive => @_props[propName].get()

            @_props[propName].set newValue

            unless equalsFunc oldValue, newValue
                if propSpec.onChange?
                    if componentDebug then console.log _getDebugPrefix(@), "props.#{propName}.onChange!", oldValue, newValue
                    propSpec.onChange.call @, oldValue, newValue


    reactSpec.componentDidMount = ->
        J._componentDomById[@_componentId] = @getDOMNode()
        J._componentDomsByName[componentName] ?= {}
        J._componentDomsByName[componentName][@_componentId] = @getDOMNode()

        componentSpec.componentDidMount?.apply @


    reactSpec.shouldComponentUpdate = (nextProps, nextState) ->
        if @_renderComp?.invalidated
            @_renderComp.stop()
            @_renderComp = null
            true
        else
            false


    reactSpec.componentDidUpdate = (prevProps, prevState) ->
        prevSetCallbacks = @_setCallbacks ? []
        delete @_setCallbacks
        callback() for callback in prevSetCallbacks

        componentSpec.componentDidUpdate?.call @, prevProps, prevState


    reactSpec.componentWillUnmount = ->
        delete J._componentById[@_componentId]
        delete J._componentDomById[@_componentId]
        delete J._componentsByName[componentName][@_componentId]
        delete J._componentDomsByName[componentName][@_componentId]

        delete @_setCallbacks

        if @_renderComp?
            @_renderComp.stop()
            @_renderComp = null

        for reactiveName, autoVar of @reactives
            autoVar.stop()

        componentSpec.componentWillUnmount?.apply @


    reactSpec.render = ->
        ###
            There are three times at which a component may be re-rendered:

            1. Synchronously by React's rendering algorithm
                This happens in the React lifecycle between the time a parent
                component's render function has returned and the time
                componentDidUpdate gets called on that parent. It's important
                for child components to render synchronously during this
                window because:
                a. It's presumably more efficient to run React's DOM diff algorithm
                   once on parent + children together, rather than once for the parent
                   followed by once per child.
                b. If the parent is setting the current component's @prop.children,
                   the parent expects its @refs to be set up synchronously when its
                   componentDidUpdate gets called (a.k.a. the time when any callbacks
                   it passed to @set get called).

            2. Asynchronously by Meteor's invalidated-computation flush
                This is the only way a component can re-render in reaction to
                something other than a change in props during a parent's re-render.

            3. The application calls @forceUpdate()

            @_renderComp's whole purpose is to invalidate, which means "let's
            rerender at the earliest time (1) or (2)".
        ###
        renderedComponent = null
        if @_renderComp?
            # We must be at time (3), a forceUpdate call.
            if @_renderComp.invalidated
                # We must be at time (2) and (3) simultaneously.
                console.warn "It looks like you're unnecessarily calling forceUpdate()
                    in #{@toString()}.render"
            @_renderComp.stop()

        @_renderComp = Tracker.autorun (c) =>
            if componentDebug then console.log _getDebugPrefix() + (if _debugDepth > 0 then " " else "") + "#{@toString()} render!#{if c.firstRun then '' else ' - from AutoRun'}"
            _debugDepth += 1
            renderedComponent = componentSpec.render.apply @
            _debugDepth -= 1

        @_renderComp.onInvalidate (c) =>
            return if c.stopped

            @_renderComp.stop()

            Tracker.afterFlush =>
                # The component may have unmounted
                return unless @isMounted()

                # Between c's invalidation time and now, the component may
                # have been re-rendered at time (1) - see comment above - in
                # which case there would be a new @_renderComp
                return unless c is @_renderComp

                @_renderComp = null
                @forceUpdate()

        renderedComponent


    reactSpec.toString = ->
        "<#{componentName}-#{@_componentId}>"


    J.components[componentName] = React.createClass reactSpec


$$ = (elemType, props, children...) ->
    args = Array.prototype.slice.call arguments

    if typeof elemType[0] is 'string' and elemType[0].toUpperCase() is elemType[0]
        throw new Meteor.Error "No component class #{elemType}." unless elemType of J.components
        args[0] = J.components[elemType]

    React.createElement.apply React, args


Meteor.startup ->
    for componentDef in componentDefinitionQueue
        J._defineComponent componentDef.name, componentDef.spec

    componentDefinitionQueue = null
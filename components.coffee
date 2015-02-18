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

componentDebug = Meteor.settings?.public?.jframework?.debug?.components ? false
componentDebugStack = []
_pushDebugFlag = (flag = null) ->
    componentDebugStack.push componentDebug
    componentDebug = flag ? componentDebug
_popDebugFlag = ->
    J.assert componentDebugStack.length > 0
    componentDebug = componentDebugStack.pop()

_debugDepth = 0
_getDebugPrefix = (component = null, tabWidth = 4) ->
    numSpaces = Math.max 0, tabWidth * (_debugDepth + 1) - 1
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
            throw new Meteor.Error "Unnecessary to define #{memberName} for JFramework components
                (in #{componentName})"

    unless _.isFunction componentSpec.render
        throw new Meteor.Error "Missing #{componentName}.render method"

    reactSpec = _.clone componentSpec
    delete reactSpec.props
    delete reactSpec.state
    delete reactSpec.reactives
    delete reactSpec.debug

    propSpecs = _.clone componentSpec.props ? {}
    propSpecs.className ?=
        type: React.PropTypes.string
    propSpecs.children ?=
        type: React.PropTypes.oneOfType [
            React.PropTypes.element
            React.PropTypes.arrayOf(React.PropTypes.element)
        ]

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
                _pushDebugFlag stateFieldSpec.debug ? componentSpec.debug

                ret = @state[stateFieldName].get()

                if componentDebug
                    console.debug _getDebugPrefix(@), "#{stateFieldName}()", ret
                _popDebugFlag()

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
                    # console.debug 'PUSH', newPath
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
        for propName, propSpec of propSpecs
            defaultProps[propName] =
                if 'default' of propSpec
                    propSpec.default
                else
                    null
        defaultProps


    reactSpec.getInitialState = ->
        @_componentId = nextComponentId
        nextComponentId += 1
        J._componentById[@_componentId] = @
        J._componentsByName[componentName] ?= {}
        J._componentsByName[componentName][@_componentId] = @

        # Check for invalid prop names in @props
        for propName, value of @props
            unless propName of propSpecs
                throw new Meteor.Error "#{componentName} has no prop #{JSON.stringify propName}.
                    Only has #{JSON.stringify _.keys propSpecs}."
        # Set up @prop
        @_props = {} # Vars for the props
        @prop = {} # Reactive getters for the props
        for propName, propSpec of propSpecs
            @_props[propName] = new J.Var @props[propName],
                tag:
                    component: @
                    tag: "#{@toString}.prop.#{propName}"
                onChange: do (propName, propSpec) => (oldValue, newValue) =>
                    if propSpec.onChange?
                        if componentDebug
                            console.debug _getDebugPrefix(@), "props.#{propName}.onChange!"
                            console.debug "        old:", J.util.consolify oldValue
                            console.debug "        new:", J.util.consolify newValue
                        propSpec.onChange.call @, oldValue, newValue

            @prop[propName] = do (propName, propSpec) => =>
                _pushDebugFlag propSpec.debug ? componentSpec.debug

                ret = @_props[propName].get()

                if componentDebug
                    console.debug _getDebugPrefix(@), "prop.#{propName}()", ret
                _popDebugFlag()

                ret

        # Set up @state
        initialState = {}
        stateFromRoute =
            if J.Routable in (componentSpec.mixins ? []) and @stateFromRoute?
                @stateFromRoute @getParams(), @_cleanQueryFromRaw()
            else
                {}
        for stateFieldName, stateFieldSpec of componentSpec.state
            if stateFromRoute[stateFieldName] isnt undefined
                initialValue = stateFromRoute[stateFieldName]
            else if _.isFunction stateFieldSpec.default
                # TODO: If the type is J.$function then use the other if-branch
                _pushDebugFlag stateFieldSpec.debug ? componentSpec.debug
                if componentDebug
                    console.debug _getDebugPrefix(@), "#{stateFieldName} !default()"
                    _debugDepth += 1

                initialValue = stateFieldSpec.default.apply @

                if componentDebug
                    console.debug _getDebugPrefix(), initialValue
                    _debugDepth -= 1
                _popDebugFlag()
            else
                initialValue = stateFieldSpec.default ? null

            initialState[stateFieldName] = new J.Var initialValue,
                tag:
                    component: @
                    tag: "#{@toString()}.state.#{stateFieldName}"
                onChange: do (stateFieldName, stateFieldSpec) => (oldValue, newValue) =>
                    if stateFieldSpec.onChange?
                        if componentDebug
                            console.debug _getDebugPrefix(@), "state.#{stateFieldName}.onChange!"
                            console.debug "        old:", J.util.consolify oldValue
                            console.debug "        new:", J.util.consolify newValue
                        stateFieldSpec.onChange.call @, oldValue, newValue

        # Set up @reactives
        @reactives = {} # reactiveName: autoVar
        for reactiveName, reactiveSpec of reactiveSpecByName
            @reactives[reactiveName] = do (reactiveName, reactiveSpec) =>
                J.AutoVar(
                    component: @
                    tag: "#{@toString()}.reactives.#{reactiveName}",

                    =>
                        _pushDebugFlag reactiveSpec.debug ? componentSpec.debug
                        if componentDebug
                            console.debug _getDebugPrefix(@), "!#{reactiveName}()"
                            _debugDepth += 1

                        try
                            retValue = reactiveSpec.val.call @
                        finally
                            if componentDebug
                                console.debug _getDebugPrefix(), retValue
                                _debugDepth -= 1
                            _popDebugFlag()

                        retValue

                    if reactiveSpec.onChange? then (oldValue, newValue) =>
                        if componentDebug
                            console.debug "    #{@toString()}.#{reactiveName}.onChange!"
                            console.debug "        old:", J.util.consolify oldValue
                            console.debug "        new:", J.util.consolify newValue
                        reactiveSpec.onChange.call @, oldValue, newValue
                    else null
                )

        # Return initialState to React
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
            @_props[propName].set newValue


    reactSpec.componentDidMount = ->
        J._componentDomById[@_componentId] = @getDOMNode()
        J._componentDomsByName[componentName] ?= {}
        J._componentDomsByName[componentName][@_componentId] = @getDOMNode()

        componentSpec.componentDidMount?.apply @


    reactSpec.shouldComponentUpdate = (nextProps, nextState) ->
        @_renderComp?.invalidated


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

        @_renderComp.stop()

        for reactiveName, autoVar of @reactives
            autoVar.stop()

        componentSpec.componentWillUnmount?.apply @


    reactSpec.render = ->
        ###
            Note: The following code is not elegant.
            It would be much better to have an AutoVar which
            always computes the latest version of the element. Unfortunately,
            in order for React to set up refs properly, we need to do the
            rendering at the right synchronous time.
        ###

        if @_renderComp?
            if @_renderComp.invalidated
                @_renderComp.stop()
            else
                throw new Meteor.Error "Called #{@toString()}.forceUpdate() - J.components don't allow
                    forceUpdate(). Use reactive expressions instead."

        # Transform J.List to array anywhere in the element children hierarchy
        # and J.Dicts to plain objects in the case of the "style" property
        transformedElement = (elem) =>
            if React.isValidElement elem
                if _.isArray elem.props.children
                    elem.props.children = (transformedElement e for e in elem.props.children)
                else if elem.props.children?
                    elem.props.children = transformedElement elem.props.children
                if elem.props.style instanceof J.Dict
                    elem.props.style = elem.props.style.toObj()
                elem
            else if elem instanceof J.List
                transformedElement e for e in elem.toArr()
            else if _.isArray elem
                transformedElement e for e in elem
            else
                elem

        element = undefined

        Tracker.autorun (c) =>
            if c.firstRun
                @_renderComp = c
                @_renderComp.tag = "#{@toString()}.render!"

            else
                if componentDebug
                    console.debug _getDebugPrefix() + (if _debugDepth > 0 then " " else "") +
                        "Invalidated #{@toString()}", c._id

                # This autorun was just here to let us respond to an invalidation
                # at flush time once. The @forceUpdate() call will now stop this
                # computation and create a new one.
                @_renderComp.stop()
                @_renderComp = null

                # If we start the new @_renderComp inside this stopped @_renderComp,
                # Meteor will automatically stop it.
                Tracker.nonreactive => @forceUpdate()

                return

            _pushDebugFlag componentSpec.debug
            if componentDebug
                console.debug _getDebugPrefix() + (if _debugDepth > 0 then " " else "") +
                    "#{@toString()} render!", c._id
                _debugDepth += 1

            try
                element = transformedElement componentSpec.render.apply @
            catch e
                throw e unless e instanceof J.VALUE_NOT_READY
            finally
                if componentDebug
                    console.debug _getDebugPrefix(), element
                    _debugDepth -= 1
                _popDebugFlag()

        if element is undefined then element =
            $$ ('div'),
                style:
                    textAlign: 'center'
                    opacity: 0.5
                ("#{@toString()} loading...")

        element


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
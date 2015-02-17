J.defineRouter = (routeGenerator) ->
    J._routeGenerator = routeGenerator

if Meteor.isServer
    # Server-side routing is broken, but it's still nice to not
    # break definitions of React components server-side,
    # and some of them try to use the ReactRouter.State mixin.
    J.Routable = {NOT_IMPLEMENTED_YET: true};

if Meteor.isClient and ReactRouter?
    # Hack J.Routable mixin as a combo of ReactRouter.State + ReactRouter.Navigation

    ###
        NOTE:
        J Framework components.coffee has some inline code that conditions
        on whether a control has J.Routable in its mixins, because we
        wanted to use features (like a Reactive) outside the React Mixin framework.
    ###

    J.Routable = _.extend _.clone(ReactRouter.State), ReactRouter.Navigation
    J.Routable.contextTypes = _.extend _.clone(ReactRouter.State.contextTypes),
        ReactRouter.Navigation.contextTypes
    _.extend J.Routable,
        _cleanQueryFromRaw: ->
            ###
                Treat x as nonexistent in all these cases:
                    x=&y=5
                    x&y=5
                    y=5
            ###
            query = {}
            for fieldName, value of @getQuery()
                if value then query[fieldName] = URI.decodeQuery(value.replace(/\*hashtag\*/, '#'))
            query

        _rawQueryFromClean: (cleanQuery) ->
            rawQuery = {}
            fieldNames = _.keys cleanQuery
            for fieldName in fieldNames
                value = cleanQuery[fieldName]
                if value then rawQuery[fieldName] = value
            rawQuery

        makeGoodPath: (routeName, params={}, query={}) ->
            URI.decodeQuery(@makePath(
                routeName,
                params,
                @_rawQueryFromClean query
            )).replace(/\ /g, '+').replace(/#/, '*hashtag*')


if Meteor.isClient then Meteor.startup ->
    J._dataSubscription = Meteor.subscribe '_jdata', J.fetching.SESSION_ID, ->
        if J._routeGenerator?
            rootRoute = J._routeGenerator()

            ReactRouter?.run rootRoute, ReactRouter.HistoryLocation, (Handler, state) ->
                React.render $$(Handler), document.body

        else
            console.warn "No router defined. Call J.defineRouter to define a router."
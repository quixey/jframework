J.dc 'LinkButton',
    props:
        onClick:
            type: React.PropTypes.func

    render: ->
        $$ ('span'),
            style:
                cursor: 'pointer'
                color: 'blue'
            onClick: @prop.onClick()
            (@prop.children())
J.dc 'Button',
    props:
        enabled:
            type: React.PropTypes.bool.isRequired
            default: true
        onClick:
            type: React.PropTypes.func
        style:
            type: React.PropTypes.object
            default: {}

    render: ->
        $$ ('button'),
            type: 'button'
            disabled: not @prop.enabled()
            onClick: (event) => @prop.onClick()? event
            style: @prop.style()
            (@prop.children())
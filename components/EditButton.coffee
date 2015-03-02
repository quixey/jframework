J.dc 'EditButton',
    props:
        onClick:
            type: React.PropTypes.func

    render: ->
        $$ ('LinkButton'),
            onClick: => @prop.onClick()? {}
            $$ ('img'),
                src: '/images/edit.png'
                style:
                    width: 16
                    height: 16
                    opacity: 0.5
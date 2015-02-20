J.dc 'Loader',
    props:
        size:
            type: React.PropTypes.number
            default: 20

    render: ->
        $$ 'img',
            src: '/images/loader.gif'
            style:
                width: @prop.size()
                height: @prop.size()
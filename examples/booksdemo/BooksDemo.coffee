J.defineModel 'Book', 'books',
    _id: $$.string
    fields:
        title: $$.string
        picUrl: $$.string
        authorId: $$.string
    reactives:
        author:
            val: -> $$.Author.fetchOne @authorId()

J.defineModel 'Author', 'authors',
    _id: $$.string
    fields:
        name: $$.string

J.defineRouter ->
    $$ (ReactRouter.Route),
        name: 'books'
        handler: J.components.BooksPage

J.defineComponent 'BooksPage',
    mixins: [J.Routable]

    state:
        limit:
            default: 5
        showAuthors:
            default: false

    reactives:
        route:
            val: ->
                query:
                    limit: @limit()
                    authors: if @showAuthors() then '1'

    stateFromRoute: (params, query) ->
        limit: if not _.isNaN parseInt query.limit then parseInt query.limit
        showAuthors: query.authors is '1'

    render: ->
        $$ ('div'),
            style:
                fontFamily: 'helvetica neue'

            $$ ('div'),
                style:
                    marginBottom: 20

                ("Limit: ")
                $$ ('input'),
                    type: 'text'
                    defaultValue: "#{@limit()}"
                    style:
                        width: 20
                        marginRight: 20
                    onChange: (e) => @limit parseInt e.target.value

                $$ ('input'),
                    type: 'checkbox'
                    checked: @showAuthors()
                    onChange: (e) => @showAuthors e.target.checked
                ("Show authors")

            # Showing the spinner while waiting for data causes our text input to lose focus.
            # To prevent this, you can replace `$$.Book.fetch(...)` with `$$.Book.tryFetch(...)?`.
            $$.Book.fetch(
                {}
                limit: @limit()
                sort: title: 1
            ).map (book, i) =>
                $$ ('TableRow'),
                    {}

                    $$ ('td'),
                        style:
                            color: 'gray'
                        ("#{i + 1}")

                    $$ ('td'),
                        {}
                        $$ ('img'),
                            src: book.picUrl()
                            style:
                                width: 50
                                padding: 10

                    $$ ('td'),
                        style:
                            width: 250

                        $$ ('div'),
                            style:
                                fontWeight: 'bold'
                            (book.title())

                        if @showAuthors() # To prevent focus-losing issues, add `and book.tryGet('author')?`
                            $$ ('div'),
                                style:
                                    color: 'gray'
                                ("by #{book.author().name()}")
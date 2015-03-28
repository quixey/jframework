authorsData = [
    _id: 'mtwain'
    name: 'Mark Twain'
,
    _id: 'jsteinbeck'
    name: 'John Steinbeck'
,
    _id: 'gorwell'
    name: 'George Orwell'
,
    _id: 'jausten'
    name: 'Jane Austen'
,
    _id: 'cdickens'
    name: 'Charles Dickens'
,
    _id: 'jpublic'
    name: 'John Q. Public'
]

booksData = [
    _id: 'aohf'
    title: 'Adventures of Huckleberry Finn'
    picUrl: 'http://isach.info/images/story/cover/adventures_of_huckleberry_finn__mark_twain.jpg'
    authorId: 'mtwain'
,
    _id: 'taots'
    title: 'The Adventures of Tom Sawyer'
    picUrl: 'http://ebookbees.com/wp-content/uploads/2014/05/the.adventures.of_.tom_.sawyer-.by_.mark_.twain_.book_.cover_.jpg'
    authorId: 'mtwain'
,
    _id: 'tgow'
    title: 'The Grapes of Wrath'
    picUrl: 'http://upload.wikimedia.org/wikipedia/en/1/1f/JohnSteinbeck_TheGrapesOfWrath.jpg'
    authorId: 'jsteinbeck'
,
    _id: 'omam'
    title: 'Of Mice and Men'
    picUrl: 'http://upload.wikimedia.org/wikipedia/en/0/01/OfMiceAndMen.jpg'
    authorId: 'jsteinbeck'
,
    _id: 'eoe'
    title: 'East of Eden'
    picUrl: 'http://upload.wikimedia.org/wikipedia/en/5/56/EastOfEden.jpg'
    authorId: 'jsteinbeck'
,
    _id: 'pap'
    title: 'Pride and Prejudice'
    picUrl: 'http://www.publicbookshelf.com/images/PridePrejudice423x630.jpg'
    authorId: 'jausten'
,
    _id: 'sas'
    title: 'Sense and Sensibility'
    picUrl: 'http://ecx.images-amazon.com/images/I/51deGt5-iIL.jpg'
    authorId: 'jausten'
,
    _id: 'acc'
    title: 'A Christmas Carol'
    picUrl: 'http://www.pagepulp.com/wp-content/18.jpg'
    authorId: 'cdickens'
,
    _id: 'ge'
    title: 'Great Expectations'
    picUrl: 'http://ecx.images-amazon.com/images/I/61buI5-QU5L._SY344_BO1,204,203,200_.jpg'
    authorId: 'cdickens'
,
    _id: 'ot'
    title: 'Oliver Twist'
    picUrl: 'http://www.images-booknode.com/book_cover/396/full/oliver-twist-396176.jpg'
    authorId: 'cdickens'
]

Meteor.startup ->
    (new $$.Author authorFields).save() for authorFields in authorsData
    (new $$.Book bookFields).save() for bookFields in booksData
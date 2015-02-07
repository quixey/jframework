J.PropTypes =
    instanceOfModel: (modelName) ->
        # Here at definition time, J.Models[modelName]
        # probably hasn't been created yet. So we'll
        # just wait until validator call time.
        validator = ->
            # Okay, it's validator call time.
            modelClass = J.models[modelName]
            unless modelClass?
                throw new Meteor.Error "Invalid modelName #{JSON.stringify modelName} in instanceOfModel"

            React.PropTypes.instanceOf(modelClass).apply @, arguments

        validator.isRequired = ->
            # Okay, it's validator call time.
            modelClass = J.models[modelName]
            unless modelClass?
                throw new Meteor.Error "Invalid modelName #{JSON.stringify modelName} in instanceOfModel"

            React.PropTypes.instanceOf(modelClass).isRequired.apply @, arguments

        validator

    # J.PropTypes.key is a pseudo-propType that the
    # _id fieldSpec can use to declare that it isn't
    # part of the Normalized Kernel of our data model, i.e.
    # the model's key() instance function computed it
    # from other fields at db-insert time.
    key: {}

    number: {}

    object: {}

    string: {}


for propTypeName, propTypeFunc of J.PropTypes
    $$[propTypeName] = propTypeFunc
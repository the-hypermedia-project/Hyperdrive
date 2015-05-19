# Hyper Blueprint

You can use Hyperdrive with *any* JSON API which is described by an
[API Blueprint](https://apiblueprint.org/). You are not limited to
Hypermedia APIs, any API Blueprint can be introspected to determine the
hypermedia controls that an API may afford to the user.

## Usage

### Entering an API via API Blueprint

Instead of entering the API as you would for a Hypermedia API you will need
to enter it via the `HyperBlueprint` extension of Hyperdrive.

If our API Blueprint is hosted on [Apiary](https://apiary.io/), you may
enter it by providing the Apiary API domain, for example
[`pollsapp`](http://docs.pollsapp.apiary.io/).

```swift
HyperBlueprint.enter(apiary: "pollsapp") { result in
  switch result {
    case .Success(let hyperdrive, let representor):
      println("Success.")

    case .Failure(let error):
      println("Failed to enter API \(error)")
  }
}
```

You may also enter an API Blueprint that you've hosted yourself:

```swift
HyperBlueprint.enter(blueprintURL: "https://raw.githubusercontent.com/apiaryio/polls-app/master/apiary.apib")
```

By default, Hyperdrive will use the `HOST` URL for your API configured in
the API Blueprint. You may also overide this in your client by providing
a custom base URL:

```swift
let root = NSURL(string: "https://polls.apiblueprint.org/")
HyperBlueprint.enter(apiary: "pollsapp", baseURL: root)
```

### Blueprint

HyperBlueprint makes extensive use of [relations][] and [MSON][]
descriptions in a blueprint to provide hypermedia controls.

#### Root transitions

By default, any safe idempotent (GET) actions which do not have any
required parameters or attributes are available as the initial transitions.
For example, the following action will be shown when we enter our API:

```markdown
## Question Collection [/questions]
+ Attributes (array[Question])

### List All Questions [POST]
+ Relation: questions
```

Which can be used via the following:

```swift
if let questions = representor.transitions["questions"] {
  // We have a transition to questions

  hyperdrive.request(questions) { result in
    // We've retreived the questions or received an error while trying to
  }
}
```

The resultant Representor for the questions collection will contain a
list of representors to the questions included. Since we declared that
the questions collection is of the type `array[Question]`,
Hyperdrive will pair this to the Question resource which looks as follows.

```markdown
## Question [/questions/{question_id}]
+ Parameters
    + question_id: 1 (required, number) - ID of the Question in form of an integer

+ Attributes
    + question: `Favourite programming language?` (string, required)
    + choices (array[Choice], required) - An array of Choice objects
```

Again, Hyperdrive can determine that the `choices` attribute of our
`Question` resource is an array of `Choice` resources. So given our questions
collection representor, we can retrieve the questions resources, and
each questions choices as follows:

```swift
if let questions = representor.representors["questions"] {
  for question in questions {
    println("Question: \(question.attributes["question"])")

    if let choices = question.representors["choices"] {
      for choice in choices {
        println("Choice: \(choice.attributes["choice"])")
      }
    }
  }
}
```

The `Choice` resource in our API Blueprint looks as follows:

```markdown
## Choice [/questions/{question_id}/choices/{choice_id}]
+ Parameters
    + question_id (required, number, `1`) ... ID of the Question in form of an integer
    + choice_id (required, number, `1`) ... ID of the Choice in form of an integer

+ Attributes
    + choice: Swift (string, required)
    + votes: 0 (number, required)

### Vote on a Choice [POST]
+ Relation: vote
```

You can see we have an action with the relation of `vote` on our Choice
resource. This is exposed in our Representor of the Choice resource. We
can follow this transition to perform this action without our client ever
knowing about the implementation details such as any URIs or HTTP methods
used in our API.

```swift
if let vote = choice.transitions["vote"] {
  hyperdrive.request(vote)
}
```

Our actions may also provide attributes, such as our action to create a new
question in our API. In the blueprint it looks as follows:

```markdown
### Create a New Question [POST]
+ Relation: create
+ Attributes
    + question (string, required) - The question
    + choices (array[string]) - A collection of choices.
+ Response 201 (application/json)
    + Attributes (Question)
```

We have declared that this action takes two attributes, question and choices.
This allows us to introspect these attributes in our transition as follows:

```swift
if let create = representor.transitions["create"] {
  println("We can create a new question with the following attributes:")

  for attribute in create.attributes {
    println(attribute)
  }
}
```

This can allow you to generate user interface based on the blueprint, or
even remove fields when they are no longer used in our API. Along with using
the attribute for user input validation.

[relations]: https://github.com/apiaryio/api-blueprint/blob/master/API%20Blueprint%20Specification.md#def-relation-section
[MSON]: https://github.com/apiaryio/api-blueprint/blob/master/API%20Blueprint%20Specification.md#7-attributes-section


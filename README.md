<img src="Hyperdrive.png" width=51 height=49 alt="Hyperdrive Logo" />

# Hyperdrive

Hyperdrive is a generic Hypermedia API client in Swift. Hyperdrive allows
you to build an application which can evolve at run-time and does not
hard-code implementation details such as URIs and HTTP methods into your
application. You simply enter your API using the root URI and explore it's
funcitonality at run-time by understanding the semantics of the domain
instead of knowledge about the implementation.

## Usage

Below is a short example of using Hyperdrive to communicate with a Hypermedia API.
An API that offers information about how it works at run-time using hyperlinks.

We're going to connect to a [Polls API](https://github.com/apiaryio/polls-api),
an API which allows you to view questions, vote for them and create new
questions with multiple-choice answers.

```swift
let hyperdrive = Hyperdrive()
```

To get started, we will enter the API from its root URI. We will pass it an
asynchronous function to be executed with a result from the API.

```swift
hyperdrive.enter("https://polls.apiblueprint.org/") { result in
  switch result {
    case Success(let representor):
      println("The API has offered us the following transitions: \(representor.transitions)")

    case Failure(let error):
      println("Unfortunately there was an error: \(error)")
  }
}
```

On success, we have a Representor, this is a structure representing the API
resource. It includes relations to other resources along with information
about how we can transition from the current state to another.

Our client understands the semantics behind “questions” and explicitly
looks for a transition to them on our API.

```swift
if let questions = representor.transitions["questions"] {
  println("Our API has a transition to a questions resource.")
} else {
  println("Looks like this API doesn’t support questions, or " +
          "the feature was removed.")
}
```

Since our API has a transition to a collection of questions, let’s retrieve
them and take a look:

```swift
hyperdrive.request(questions) { result in
  switch result {
    case Success(let representor):
      println("We’ve received a representor for the questions.")

    case Failure(let error):
      println("There was a problem retreiving the questions: \(error)")
  }
}
```

On success, we have another representor representing the questions resource in
our API.

```swift
if let questions = representor.representors["questions"] {
  // Our representor includes a collection of Question resources.
  // Let’s use map to call viewQuestion for each one
  map(questions, viewQuestion)
} else {
  println("Looks like there are no questions yet.")
  println("Perhaps the API offers us the ability to create a question?")
}
```

With every question in this resource, we will call our `viewQuestion` function:

```swift
func viewQuestion(question:Representor<HTTPTransition>) {
  println(question.attributes["question"])

  if let choices = question.representors["choices"] {
    for choice in choices {
      let text = choice.attributes["choice"]
      let votes = choice.attributes["votes"]
      println('-> \(text) (\(votes))')
    }
  } else {
    println("-> This question does not have any choices.")
  }
}
```

### Transitioning from one state to another

A representor includes information on how to transition from one state to
another. For example, we might be presented with the ability to delete
one of our questions:

```swift
if let delete = question.transitions["delete"] {
  // We can perform this transition with Hyperdrive
  hyperdrive.request(delete)
} else {
  println("The API doesn’t offer us the ability to delete a question.")
  println("Let’s gracefully handle the lack of this feature and " +
          "remove deletion from our user interface.")
}
```

We may also be presented with an option to vote on a choice:

```swift
if let vote = choice.transitions["vote"] {
  hyperdrive.request(vote)
}
```

#### Transitions with attributes

A transition may also provide attributes for performing the transition. For
example, our API may afford us to perform a transition to create a new
question.

```swift
if let create = questions.transitions["create"] {
  let attributes = [
    "question": "Favourite programming language?",
    "choices": [
      "Swift",
      "Python",
      "Ruby",
    ]
  ]

  hyperdrive.request(create, attributes)
} else {
  // Our API doesn’t allow us to create a question. We should remove the
  // ability to create a question in our user interface.
  // This transition may only be available to certain users.
}
```

Transitions also include the available attributes you can send for run-time
introspection.

```swift
create.attributes
```

This allows you to generate user interface that can adapt to changes from the
API. You can also use validation for an attribute.

## Content Types

Hyperdrive supports the following Hypermedia content-types:

- [Siren](https://github.com/kevinswiber/siren) (`application/vnd.siren+json`)
- [HAL](http://stateless.co/hal_specification.html) (`application/hal+json`)

For APIs which do not support Hypermedia content types, you may use an API
description in form of an [API Blueprint](Blueprint.md) to load these controls.

## Installation

[CocoaPods](http://cocoapods.org/) is the recommended installation method.

```ruby
pod 'Hyperdrive'
```

## License

Hyperdrive is released under the MIT license. See [LICENSE](LICENSE).


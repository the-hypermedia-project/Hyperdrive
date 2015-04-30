<img src="Hyperdrive.png" width=51 height=49 alt="Hyperdrive Logo" />

# Hyperdrive

A simple Hypermedia API client in Swift, which makes use of the [Representor](https://github.com/the-hypermedia-project/representor-swift) pattern.

Hyperdrive supports the following content-types:

- [Siren]() (`application/vnd.siren+json`)
- [HAL]() (`application/hal+json`)

## Usage

Below is a short example of using Hyperdrive talking to a Hypermedia API. We
will connect to a [Polls API](https://github.com/apiaryio/polls-api), an
API which allows you to view questions, vote for them and create questions.

```swift
let hyperdrive = Hyperdrive()
```

To get started, we will enter the API from its root URI. We will pass it an
asynchronous function to be executed with a result from the API.

```swift
hyperdrive.enter("https://polls.apiblueprint.org/") { result in
  switch result {
    case Success(let representor):
      println("The API has offered us the following links: \(representor.links)")

    case Failure(let error):
      println("Unfortunately there was an error: \(error)")
  }
}
```

On success, we have a Representor, which allows us to view the attributes
associated with our resource, along with any relations to other resources in addition to
any transitions to other states we may be able to perform.

Our client understands the semantics behind “questions” and explicitly
looks for a link to them on our API.

```swift
if let questions = representor.links["questions"] {
  println("Our API has a link to a questions resource.")
} else {
  println("Looks like this API doesn’t support questions, or " +
          "the feature was removed.")
}
```

Since our API has a link to a collection of questions, let’s retrieve them and take a look:

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

With every question, we will call our `viewQuestion` function:

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

## Installation

[CocoaPods](http://cocoapods.org/) is the recommended installation method.

```ruby
pod 'Hyperdrive', :git => 'https://github.com/kylef/Hyperdrive'
```

## License

Hyperdrive is released under the MIT license. See [LICENSE](LICENSE).


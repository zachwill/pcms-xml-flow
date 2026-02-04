# Guide

# Getting Started

Datastar simplifies frontend development, allowing you to build backend-driven, interactive UIs using a [hypermedia-first](https://hypermedia.systems/hypermedia-a-reintroduction/) approach that extends and enhances HTML. 

Datastar provides backend reactivity like [htmx](https://htmx.org/) and frontend reactivity like [Alpine.js](https://alpinejs.dev/) in a lightweight frontend framework that doesn’t require any npm packages or other dependencies. It provides two primary functions: 

1. Modify the DOM and state by sending events from your backend.
2. Build reactivity into your frontend using standard `data-*` HTML attributes.

> Other useful resources include an AI-generated [deep wiki](https://deepwiki.com/starfederation/datastar), LLM-ingestible [code samples](https://context7.com/websites/data-star_dev), and [single-page docs](https://www.google.com/search?q=/docs). 
> 
> 

## Installation

The quickest way to use Datastar is to include it using a `script` tag that fetches it from a CDN. 

```html
<script type="module" src="https://cdn.jsdelivr.net/gh/starfederation/datastar@1.0.0-RC.7/bundles/datastar.js"></script>

```



If you prefer to host the file yourself, download the [script](https://cdn.jsdelivr.net/gh/starfederation/datastar@1.0.0-RC.7/bundles/datastar.js) or create your own bundle using the [bundler](https://www.google.com/search?q=/bundler), then include it from the appropriate path. 

```html
<script type="module" src="/path/to/datastar.js"></script>

```



To import Datastar using a package manager such as npm, Deno, or Bun, you can use an import statement. 

```javascript
// @ts-expect-error (only required for TypeScript projects)
import 'https://cdn.jsdelivr.net/gh/starfederation/datastar@1.0.0-RC.7/bundles/datastar.js'

```



## `data-*`

At the core of Datastar are [`data-*`](https://www.google.com/search?q=%5Bhttps://developer.mozilla.org/en-US/docs/Web/HTML/How_to/Use_data_attributes%5D(https://developer.mozilla.org/en-US/docs/Web/HTML/How_to/Use_data_attributes)) HTML attributes (hence the name). They allow you to add reactivity to your frontend and interact with your backend in a declarative way. 

> The Datastar [VSCode extension](https://marketplace.visualstudio.com/items?itemName=starfederation.datastar-vscode) and [IntelliJ plugin](https://plugins.jetbrains.com/plugin/26072-datastar-support) provide autocompletion for all available `data-*` attributes. 
> 
> 

The [`data-on`](https://www.google.com/search?q=/reference/attributes%23data-on) attribute can be used to attach an event listener to an element and execute an expression whenever the event is triggered. The value of the attribute is a [Datastar expression](https://www.google.com/search?q=/guide/datastar_expressions) in which JavaScript can be used. 

```html
<button data-on:click="alert('I’m sorry, Dave. I’m afraid I can’t do that.')">
    Open the pod bay doors, HAL.
</button>

```



## Patching Elements

With Datastar, the backend *drives* the frontend by **patching** (adding, updating and removing) HTML elements in the DOM. 

Datastar receives elements from the backend and manipulates the DOM using a morphing strategy (by default). Morphing ensures that only modified parts of the DOM are updated, and that only data attributes that have changed are [reapplied](https://www.google.com/search?q=/reference/attributes%23attribute-evaluation-order), preserving state and improving performance. 

Datastar provides [actions](https://www.google.com/search?q=/reference/actions%23backend-actions) for sending requests to the backend. The [`@get()`](https://www.google.com/search?q=/reference/actions%23get) action sends a `GET` request to the provided URL using a [fetch](https://developer.mozilla.org/en-US/docs/Web/API/Fetch_API) request. 

```html
<button data-on:click="@get('/endpoint')">
    Open the pod bay doors, HAL.
</button>
<div id="hal"></div>

```



> Actions in Datastar are helper functions that have the syntax `@actionName()`. Read more about actions in the [reference](https://www.google.com/search?q=/reference/actions). 
> 
> 

If the response has a `content-type` of `text/html`, the top-level HTML elements will be morphed into the existing DOM based on the element IDs. 

```html
<div id="hal">
    I’m sorry, Dave. I’m afraid I can’t do that.
</div>

```



We call this a “Patch Elements” event because multiple elements can be patched into the DOM at once. 

In the example above, the DOM must contain an element with a `hal` ID in order for morphing to work. Other [patching strategies](https://www.google.com/search?q=/reference/sse_events%23datastar-patch-elements) are available, but morph is the best and simplest choice in most scenarios. 

If the response has a `content-type` of `text/event-stream`, it can contain zero or more [SSE events](https://www.google.com/search?q=/reference/sse_events). The example above can be replicated using a `datastar-patch-elements` SSE event. 

```text
event: datastar-patch-elements
data: elements <div id="hal">
data: elements     I’m sorry, Dave. I’m afraid I can’t do that.
data: elements </div>

```



Because we can send as many events as we want in a stream, and because it can be a long-lived connection, we can extend the example above to first send HAL’s response and then, after a few seconds, reset the text. 

```text
event: datastar-patch-elements
data: elements <div id="hal">
data: elements      I’m sorry, Dave. I’m afraid I can’t do that.
data: elements </div>

event: datastar-patch-elements
data: elements <div id="hal">
data: elements     Waiting for an order...
data: elements </div>

```



> In addition to your browser’s dev tools, the [Datastar Inspector](https://www.google.com/search?q=/datastar_pro%23datastar-inspector) can be used to monitor and inspect SSE events received by Datastar. 
> 
> 

---

# Reactive Signals

In a hypermedia approach, the backend drives state to the frontend and acts as the primary source of truth. It’s up to the backend to determine what actions the user can take next by patching appropriate elements in the DOM. 

Sometimes, however, you may need access to frontend state that’s driven by user interactions. Click, input and keydown events are some of the more common user events that you’ll want your frontend to be able to react to. 

Datastar uses *signals* to manage frontend state. You can think of signals as reactive variables that automatically track and propagate changes in and to [Datastar expressions](https://www.google.com/search?q=/guide/datastar_expressions). Signals are denoted using the `$` prefix. 

## Data Attributes

Datastar allows you to add reactivity to your frontend and interact with your backend in a declarative way using [custom `data-*` attributes](https://www.google.com/search?q=%5Bhttps://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Global_attributes/data-%5D(https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Global_attributes/data-)*). 

### `data-bind`

The [`data-bind`](https://www.google.com/search?q=/reference/attributes%23data-bind) attribute sets up two-way data binding on any HTML element that receives user input or selections. These include `input`, `textarea`, `select`, `checkbox` and `radio` elements, as well as web components whose value can be made reactive. 

```html
<input data-bind:foo />

```



This creates a new signal that can be called using `$foo`, and binds it to the element’s value. If either is changed, the other automatically updates. 

You can accomplish the same thing passing the signal name as a *value*. This syntax can be more convenient to use with some templating languages. 

```html
<input data-bind="foo" />

```



According to the [HTML spec](https://www.google.com/search?q=https://developer.mozilla.org/en-US/docs/Web/HTML/Global_attributes/data-*), all [`data-*`](https://www.google.com/search?q=%5Bhttps://developer.mozilla.org/en-US/docs/Web/HTML/How_to/Use_data_attributes%5D(https://developer.mozilla.org/en-US/docs/Web/HTML/How_to/Use_data_attributes)) attributes are case-insensitive. When Datastar processes these attributes, hyphenated names are automatically converted to camel case by removing hyphens and uppercasing the letter following each hyphen. For example, `data-bind:foo-bar` creates a signal named `$fooBar`. 

```html
<input data-bind:foo-bar />
<input data-bind="fooBar" />

```



### `data-text`

The [`data-text`](https://www.google.com/search?q=/reference/attributes%23data-text) attribute sets the text content of an element to the value of a signal. The `$` prefix is required to denote a signal. 

```html
<input data-bind:foo-bar />
<div data-text="$fooBar"></div>

```



The value of the `data-text` attribute is a [Datastar expression](https://www.google.com/search?q=/guide/datastar_expressions) that is evaluated, meaning that we can use JavaScript in it. 

```html
<input data-bind:foo-bar />
<div data-text="$fooBar.toUpperCase()"></div>

```



### `data-computed`

The [`data-computed`](https://www.google.com/search?q=/reference/attributes%23data-computed) attribute creates a new signal that is derived from a reactive expression. The computed signal is read-only, and its value is automatically updated when any signals in the expression are updated. 

```html
<input data-bind:foo-bar />
<div data-computed:repeated="$fooBar.repeat(2)" data-text="$repeated"></div>

```



This results in the `$repeated` signal’s value always being equal to the value of the `$fooBar` signal repeated twice. Computed signals are useful for memoizing expressions containing other signals. 

### `data-show`

The [`data-show`](https://www.google.com/search?q=/reference/attributes%23data-show) attribute can be used to show or hide an element based on whether an expression evaluates to `true` or `false`. 

```html
<input data-bind:foo-bar />
<button data-show="$fooBar != ''">
    Save
</button>

```



This results in the button being visible only when the input value is *not* an empty string. This could also be shortened to `data-show="$fooBar"`. 

Since the button is visible until Datastar processes the `data-show` attribute, it’s a good idea to set its initial style to `display: none` to prevent a flash of unwanted content. 

```html
<input data-bind:foo-bar />
<button data-show="$fooBar != ''" style="display: none">
    Save
</button>

```



### `data-class`

The [`data-class`](https://www.google.com/search?q=/reference/attributes%23data-class) attribute allows us to add or remove an element’s class based on an expression. 

```html
<input data-bind:foo-bar />
<button data-class:success="$fooBar != ''">
    Save
</button>

```



If the expression evaluates to `true`, the `success` class is added to the element, otherwise it is removed. 

Unlike the `data-bind` attribute, in which hyphenated names are converted to camel case, the `data-class` attribute converts the class name to kebab case. For example, `data-class:font-bold` adds or removes the `font-bold` class. 

```html
<button data-class:font-bold="$fooBar == 'strong'">
    Save
</button>

```



The `data-class` attribute can also be used to add or remove multiple classes from an element using a set of key-value pairs, where the keys represent class names and the values represent expressions. 

```html
<button data-class="{success: $fooBar != '', 'font-bold': $fooBar == 'strong'}">
    Save
</button>

```



Note how the `font-bold` key must be wrapped in quotes because it contains a hyphen. 

### `data-attr`

The [`data-attr`](https://www.google.com/search?q=/reference/attributes%23data-attr) attribute can be used to bind the value of any HTML attribute to an expression. 

```html
<input data-bind:foo />
<button data-attr:disabled="$foo == ''">
    Save
</button>

```



This results in a `disabled` attribute being given the value `true` whenever the input is an empty string. 

The `data-attr` attribute also converts the attribute name to kebab case, since HTML attributes are typically written in kebab case. For example, `data-attr:aria-hidden` sets the value of the `aria-hidden` attribute. 

```html
<button data-attr:aria-hidden="$foo">Save</button>

```



The `data-attr` attribute can also be used to set the values of multiple attributes on an element using a set of key-value pairs, where the keys represent attribute names and the values represent expressions. 

```html
<button data-attr="{disabled: $foo == '', 'aria-hidden': $foo}">Save</button>

```



### `data-signals`

Signals are globally accessible from anywhere in the DOM. So far, we’ve created signals on the fly using `data-bind` and `data-computed`. If a signal is used without having been created, it will be created automatically and its value set to an empty string. 

Another way to create signals is using the [`data-signals`](https://www.google.com/search?q=/reference/attributes%23data-signals) attribute, which patches (adds, updates or removes) one or more signals into the existing signals. 

```html
<div data-signals:foo-bar="1"></div>

```



Signals can be nested using dot-notation. 

```html
<div data-signals:form.baz="2"></div>

```



Like the `data-bind` attribute, hyphenated names used with `data-signals` are automatically converted to camel case by removing hyphens and uppercasing the letter following each hyphen. 

```html
<div data-signals:foo-bar="1"
     data-text="$fooBar"
></div>

```



The `data-signals` attribute can also be used to patch multiple signals using a set of key-value pairs, where the keys represent signal names and the values represent expressions. Nested signals can be created using nested objects. 

```html
<div data-signals="{fooBar: 1, form: {baz: 2}}"></div>

```



### `data-on`

The [`data-on`](https://www.google.com/search?q=/reference/attributes%23data-on) attribute can be used to attach an event listener to an element and run an expression whenever the event is triggered. 

```html
<input data-bind:foo />
<button data-on:click="$foo = ''">
    Reset
</button>

```



This results in the `$foo` signal’s value being set to an empty string whenever the button element is clicked. This can be used with any valid event name such as `data-on:keydown`, `data-on:mouseover`, etc. 

Custom events can also be used. Like the `data-class` attribute, the `data-on` attribute converts the event name to kebab case. For example, `data-on:custom-event` listens for the `custom-event` event. 

```html
<div data-on:my-event="$foo = ''">
    <input data-bind:foo />
</div>

```



## Frontend Reactivity

Datastar’s data attributes enable declarative signals and expressions, providing a simple yet powerful way to add reactivity to the frontend. 

Datastar expressions are strings that are evaluated by Datastar [attributes](https://www.google.com/search?q=/reference/attributes) and [actions](https://www.google.com/search?q=/reference/actions). 

## Patching Signals

Remember that in a hypermedia approach, the backend drives state to the frontend. Just like with elements, frontend signals can be **patched** (added, updated and removed) from the backend using [backend actions](https://www.google.com/search?q=/reference/actions%23backend-actions). 

```html
<div data-signals:hal="'...'">
    <button data-on:click="@get('/endpoint')">
        HAL, do you read me?
    </button>
    <div data-text="$hal"></div>
</div>

```



If a response has a `content-type` of `application/json`, the signal values are patched into the frontend signals. We call this a “Patch Signals” event because multiple signals can be patched (using [JSON Merge Patch RFC 7396](https://datatracker.ietf.org/doc/rfc7396/)) into the existing signals. 

```json
{"hal": "Affirmative, Dave. I read you."}

```



If the response has a `content-type` of `text/event-stream`, it can contain zero or more [SSE events](https://www.google.com/search?q=/reference/sse_events). The example above can be replicated using a `datastar-patch-signals` SSE event. 

```text
event: datastar-patch-signals
data: signals {hal: 'Affirmative, Dave. I read you.'}

```



Because we can send as many events as we want in a stream, and because it can be a long-lived connection, we can extend the example above to first set the `hal` signal to an “affirmative” response and then, after a second, reset the signal. 

```text
event: datastar-patch-signals
data: signals {hal: 'Affirmative, Dave. I read you.'}

// Wait 1 second

event: datastar-patch-signals
data: signals {hal: '...'}

```



> In addition to your browser’s dev tools, the [Datastar Inspector](https://www.google.com/search?q=/datastar_pro%23datastar-inspector) can be used to monitor and inspect SSE events received by Datastar. 
> 
> 

---

# Datastar Expressions

Datastar expressions are strings that are evaluated by `data-*` attributes. While they are similar to JavaScript, there are some important differences that make them more powerful for declarative hypermedia applications. 

## Datastar Expressions

A variable `el` is available in every Datastar expression, representing the element that the attribute is attached to. 

```html
<div data-text="el.offsetHeight"></div>

```



When Datastar evaluates the expression `$foo`, it first converts it to the signal value, and then evaluates that expression in a sandboxed context. This means that JavaScript can be used in Datastar expressions. 

```html
<div data-text="$foo.length"></div>

```



JavaScript operators are also available in Datastar expressions. This includes (but is not limited to) the ternary operator `?:`, the logical OR operator `||`, and the logical AND operator `&&`. 

```html
// Output one of two values, depending on the truthiness of a signal
<div data-text="$landingGearRetracted ? 'Ready' : 'Waiting'"></div>

// Show a countdown if the signal is truthy or the time remaining is less than 10 seconds
<div data-show="$landingGearRetracted || $timeRemaining < 10">
    Countdown
</div>

// Only send a request if the signal is truthy
<button data-on:click="$landingGearRetracted && @post('/launch')">
    Launch
</button>

```



Multiple statements can be used in a single expression by separating them with a semicolon. 

```html
<div data-signals:foo="1">
    <button data-on:click="$landingGearRetracted = true; @post('/launch')">
        Force launch
    </button>
</div>

```



## Using JavaScript

Most of your JavaScript logic should go in `data-*` attributes, since reactive signals and actions only work in [Datastar expressions](https://www.google.com/search?q=/guide/datastar_expressions). 

Any JavaScript functionality you require that cannot belong in `data-*` attributes should be extracted out into [external scripts](https://www.google.com/search?q=%23external-scripts) or, better yet, [web components](https://www.google.com/search?q=%23web-components). 

> Always encapsulate state and send **props down, events up**. 
> 
> 

### External Scripts

When using external scripts, you should pass data into functions via arguments and return a result. Alternatively, listen for custom events dispatched from them (props down, events up). 

```html
<div data-signals:result>
    <input data-bind:foo 
           data-on:input="$result = myfunction($foo)"
    >
    <span data-text="$result"></span>
</div>

```



```javascript
function myfunction(data) {
    return `You entered: ${data}`;
}

```



### Web Components

[Web components](https://developer.mozilla.org/en-US/docs/Web/API/Web_components) allow you create reusable, encapsulated, custom elements. 

When using web components, pass data into them via attributes and listen for custom events dispatched from them (*props down, events up*). 

```html
<div data-signals:result="''">
    <input data-bind:foo />
    <my-component
        data-attr:src="$foo"
        data-on:mycustomevent="$result = evt.detail.value"
    ></my-component>
    <span data-text="$result"></span>
</div>

```



## Executing Scripts

Just like elements and signals, the backend can also send JavaScript to be executed on the frontend using [backend actions](https://www.google.com/search?q=/reference/actions%23backend-actions). 

If a response has a `content-type` of `text/javascript`, the value will be executed as JavaScript in the browser. 

If the response has a `content-type` of `text/event-stream`, it can contain zero or more [SSE events](https://www.google.com/search?q=/reference/sse_events). The example above can be replicated by including a `script` tag inside of a `datastar-patch-elements` SSE event. 

```text
event: datastar-patch-elements
data: elements <div id="hal">
data: elements     <script>alert('This mission is too important for me to allow you to jeopardize it.')</script>
data: elements </div>

```



If you *only* want to execute a script, you can `append` the script tag to the `body`. 

```text
event: datastar-patch-elements
data: mode append
data: selector body
data: elements <script>alert('This mission is too important for me to allow you to jeopardize it.')</script>

```



---

# Backend Requests

Between [attributes](https://www.google.com/search?q=/reference/attributes) and [actions](https://www.google.com/search?q=/reference/actions), Datastar provides you with everything you need to build hypermedia-driven applications. 

## Sending Signals

By default, all signals (except for local signals whose keys begin with an underscore) are sent in an object with every backend request. When using a `GET` request, the signals are sent as a `datastar` query parameter, otherwise they are sent as a JSON body. 

### Nesting Signals

Signals can be nested, making it easier to target signals in a more granular way on the backend. 

Using dot-notation:

```html
<div data-signals:foo.bar="1"></div>

```



Using object syntax:

```html
<div data-signals="{foo: {bar: 1}}"></div>

```



Using two-way binding:

```html
<input data-bind:foo.bar />

```



A practical use-case of nested signals is when you have repetition of state on a page, and use the [toggleAll()](https://www.google.com/search?q=/reference/actions%23toggleAll) action to toggle the state of all menus at once. 

## Reading Signals

To read signals from the backend, JSON decode the `datastar` query param for `GET` requests, and the request body for all other methods. 

## SSE Events

Datastar can stream zero or more [Server-Sent Events](https://developer.mozilla.org/en-US/docs/Web/API/Server-sent_events) (SSE) from the web server to the browser. 

> The [Datastar Inspector](https://www.google.com/search?q=/datastar_pro%23datastar-inspector) can be used to monitor and inspect SSE events received by Datastar. 
> 
> 

### `data-indicator`

The [`data-indicator`](https://www.google.com/search?q=/reference/attributes%23data-indicator) attribute sets the value of a signal to `true` while the request is in flight, otherwise `false`. We can use this signal to show a loading indicator. 

```html
<div id="question"></div>
<button
    data-on:click="@get('/actions/quiz')"
    data-indicator:fetching
>
    Fetch a question
</button>
<div data-class:loading="$fetching" class="indicator"></div>

```



## Backend Actions

We’re not limited to sending just `GET` requests. Datastar provides [backend actions](https://www.google.com/search?q=/reference/actions%23backend-actions) for each of the methods available: `@get()`, `@post()`, `@put()`, `@patch()` and `@delete()`. 

---

# The Tao of Datastar

Datastar is just a tool. The Tao of Datastar, or “the Datastar way” as it is often referred to, is a set of opinions from the core team on how to best use Datastar to build maintainable, scalable, high-performance web apps. 

## State in the Right Place

Most state should live in the backend. Since the frontend is exposed to the user, the backend should be the source of truth for your application state. 

## Start with the Defaults

The default configuration options are the recommended settings for the majority of applications. 

## Patch Elements & Signals

Since the backend is the source of truth, it should *drive* the frontend by **patching** (adding, updating and removing) HTML elements and signals. 

## Use Signals Sparingly

Overusing signals typically indicates trying to manage state on the frontend. Favor fetching current state from the backend rather than pre-loading and assuming frontend state is current. A good rule of thumb is to *only* use signals for user interactions (e.g. toggling element visibility) and for sending new state to the backend (e.g. by binding signals to form input elements). 

## In Morph We Trust

Morphing ensures that only modified parts of the DOM are updated, preserving state and improving performance. This allows you to send down large chunks of the DOM tree (all the way up to the `html` tag). 

## SSE Responses

[SSE](https://html.spec.whatwg.org/multipage/server-sent-events.html) responses allow you to send `0` to `n` events, in which you can [patch elements](https://www.google.com/search?q=/guide/getting_started/%23patching-elements), [patch signals](https://www.google.com/search?q=/guide/reactive_signals%23patching-signals), and [execute scripts](https://www.google.com/search?q=/guide/datastar_expressions%23executing-scripts). 

## Compression

Since SSE responses stream events from the backend and morphing allows sending large chunks of DOM, compressing the response is a natural choice. Compression ratios of 200:1 are not uncommon when compressing streams using Brotli. 

## Backend Templating

Since your backend generates your HTML, you can and should use your templating language to [keep things DRY](https://www.google.com/search?q=/how_tos/keep_datastar_code_dry) (Don’t Repeat Yourself). 

## Page Navigation

Use the [anchor element](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/a) (`<a>`) to navigate to a new page, or a [redirect](https://www.google.com/search?q=/how_tos/redirect_the_page_from_the_backend) if redirecting from the backend. For smooth page transitions, use the [View Transition API](https://developer.mozilla.org/en-US/docs/Web/API/View_Transition_API). 

## Browser History

Browsers automatically keep a history of pages visited. As soon as you start trying to manage browser history yourself, you are adding complexity. 

## CQRS

[CQRS](https://martinfowler.com/bliki/CQRS.html) makes it possible to have a single long-lived request to receive updates from the backend (reads), while making multiple short-lived requests to the backend (writes). 

## Loading Indicators

Loading indicators inform the user that an action is in progress. Use the [`data-indicator`](https://www.google.com/search?q=/reference/attributes%23data-indicator) attribute to show loading indicators on elements that trigger backend requests. 

## Optimistic Updates

Optimistic updates are when the UI updates immediately as if an operation succeeded, before the backend actually confirms it. Rather than deceive the user, use [loading indicators](https://www.google.com/search?q=%23loading-indicators) to show the user that the action is in progress. 

## Accessibility

The web should be accessible to everyone. Datastar stays out of your way and leaves [accessibility](https://developer.mozilla.org/en-US/docs/Web/Accessibility) to you. Use semantic HTML and apply ARIA where it makes sense. 

---

# Reference

# Attributes

Data attributes are [evaluated in the order](https://www.google.com/search?q=%23attribute-evaluation-order) they appear in the DOM. 

### `data-attr`

Sets the value of any HTML attribute to an expression, and keeps it in sync. 

```html
<div data-attr:aria-label="$foo"></div>

```



You can also set values of multiple attributes using a key-value pair object:

```html
<div data-attr="{'aria-label': $foo, disabled: $bar}"></div>

```



### `data-bind`

Creates a signal (if one doesn’t already exist) and sets up two-way data binding between it and an element’s value. 

```html
<input data-bind:foo />
<input data-bind="foo" />

```



**Modifiers:**

* 
`__case` – Converts the casing of the signal name (`.camel`, `.kebab`, `.snake`, `.pascal`). 



### `data-class`

Adds or removes a class to or from an element based on an expression. 

```html
<div data-class:font-bold="$foo == 'strong'"></div>
<div data-class="{success: $foo != '', 'font-bold': $foo == 'strong'}"></div>

```



### `data-computed`

Creates a signal that is computed based on an expression. The computed signal is read-only. 

```html
<div data-computed:foo="$bar + $baz"></div>

```



**Modifiers:** `__case` 

### `data-effect`

Executes an expression on page load and whenever any signals in the expression change. 

```html
<div data-effect="$foo = $bar + $baz"></div>

```



### `data-ignore`

Tells Datastar to ignore an element and its descendants. 

```html
<div data-ignore>
    <div>Datastar will not process this element.</div>
</div>

```



**Modifiers:** `__self` (only ignore the element itself, not descendants). 

### `data-ignore-morph`

Tells the `PatchElements` watcher to skip processing an element and its children when morphing. 

### `data-indicator`

Creates a signal and sets its value to `true` while a fetch request is in flight, otherwise `false`. 

```html
<button data-on:click="@get('/endpoint')" data-indicator:fetching></button>

```



### `data-init`

Runs an expression when the attribute is initialized (page load, patch, etc.). 

```html
<div data-init="$count = 1"></div>

```



**Modifiers:** `__delay`, `__viewtransition`. 

### `data-json-signals`

Sets the text content of an element to a reactive JSON stringified version of signals. 

```html
<pre data-json-signals></pre>
<pre data-json-signals="{include: /user/}"></pre>

```



**Modifiers:** `__terse`. 

### `data-on`

Attaches an event listener to an element, executing an expression whenever the event is triggered. 

```html
<button data-on:click="$foo = ''">Reset</button>

```



**Modifiers:** `__once`, `__passive`, `__capture`, `__case`, `__delay`, `__debounce`, `__throttle`, `__viewtransition`, `__window`, `__outside`, `__prevent`, `__stop`. 

### `data-on-intersect`

Runs an expression when the element intersects with the viewport. 

```html
<div data-on-intersect="$intersected = true"></div>

```



**Modifiers:** `__once`, `__exit`, `__half`, `__full`, `__threshold`, `__delay`, `__debounce`, `__throttle`, `__viewtransition`. 

### `data-on-interval`

Runs an expression at a regular interval (default 1s). 

```html
<div data-on-interval="$count++"></div>

```



**Modifiers:** `__duration`, `__viewtransition`. 

### `data-on-signal-patch`

Runs an expression whenever any signals are patched. 

```html
<div data-on-signal-patch="console.log('Signal patch:', patch)"></div>

```



**Modifiers:** `__delay`, `__debounce`, `__throttle`. 

### `data-on-signal-patch-filter`

Filters which signals to watch when using the `data-on-signal-patch` attribute. 

```html
<div data-on-signal-patch-filter="{include: /^counter$/}"></div>

```



### `data-preserve-attr`

Preserves the value of an attribute when morphing DOM elements. 

```html
<details open data-preserve-attr="open">
    <summary>Title</summary>
</details>

```



### `data-ref`

Creates a new signal that is a reference to the element on which the data attribute is placed. 

```html
<div data-ref:foo></div>

```



### `data-show`

Shows or hides an element based on whether an expression evaluates to `true` or `false`. 

```html
<div data-show="$foo"></div>

```



### `data-signals`

Patches (adds, updates or removes) one or more signals into the existing signals. 

```html
<div data-signals:foo="1"></div>
<div data-signals="{foo: {bar: 1, baz: 2}}"></div>

```



**Modifiers:** `__case`, `__ifmissing`. 

### `data-style`

Sets the value of inline CSS styles on an element based on an expression, and keeps them in sync. 

```html
<div data-style:display="$hiding && 'none'"></div>

```



### `data-text`

Binds the text content of an element to an expression. 

```html
<div data-text="$foo"></div>

```



## Pro Attributes

### `data-animate`

Allows you to animate element attributes over time. 

### `data-custom-validity`

Allows you to add custom validity to an element using an expression. 

### `data-on-raf`

Runs an expression on every `requestAnimationFrame` event. 

### `data-on-resize`

Runs an expression whenever an element’s dimensions change. 

### `data-persist`

Persists signals in local storage. 

### `data-query-string`

Syncs query string params to signal values. 

### `data-replace-url`

Replaces the URL in the browser without reloading the page. 

### `data-scroll-into-view`

Scrolls the element into view. 

### `data-rocket`

Creates a Rocket web component. 

### `data-view-transition`

Sets the `view-transition-name` style attribute explicitly. 

---

# Rocket (Alpha)

Rocket is a [Datastar Pro](https://www.google.com/search?q=/datastar_pro) plugin that bridges Web Components with Datastar’s reactive system. 

> Rocket should be used sparingly. For most applications, standard Datastar templates and global signals are sufficient. 
> 
> 

Rocket components are defined using a HTML `template` element with the `data-rocket:my-component` attribute. Component signals are automatically scoped with `$$`. 

## Examples

**Defining a component:**

```html
<template data-rocket:my-counter>
  <script>
    $$count = 0  
  </script>
  <button data-on:click="$$count++">
    Count: <span data-text="$$count"></span>
  </button>
</template>

```



**Usage:**

```html
<my-counter></my-counter>

```



---

# Actions

Datastar provides actions (helper functions) that can be used in Datastar expressions. 

### `@peek()`

Allows accessing signals without subscribing to their changes in expressions. 

### `@setAll()`

Sets the value of all matching signals. 

### `@toggleAll()`

Toggles the boolean value of all matching signals. 

## Backend Actions

### `@get()`, `@post()`, `@put()`, `@patch()`, `@delete()`

Sends a request to the backend using the Fetch API. The URI can be any valid endpoint and the response must contain zero or more [Datastar SSE events](https://www.google.com/search?q=/reference/sse_events). 

**Options:**

* `contentType`: `json` (default) or `form`.
* `filterSignals`: Include/exclude specific signals.
* `openWhenHidden`: Keep connection open when page hidden.
* `headers`: Object containing headers.
* `requestCancellation`: `auto` (default), `disabled`, or an `AbortController`.




## Pro Actions

### `@clipboard()`

Copies text to clipboard. 

### `@fit()`

Linearly interpolates a value from one range to another. 

---

# SSE Events

Responses to backend actions with a content type of `text/event-stream` can contain zero or more Datastar SSE events. 

## Event Types

### `datastar-patch-elements`

Patches one or more elements in the DOM. Options: `selector`, `mode` (outer, inner, replace, prepend, append, before, after, remove), `useViewTransition`. 

### `datastar-patch-signals`

Patches signals into the existing signals on the page. 

---

# SDKs

Datastar provides backend SDKs for:

* 
[Clojure](https://github.com/starfederation/datastar-clojure) 


* 
[C#](https://github.com/starfederation/datastar-dotnet/) 


* 
[Go](https://github.com/starfederation/datastar-go) 


* 
[Java](https://github.com/starfederation/datastar-java) 


* 
[Kotlin](https://github.com/starfederation/datastar-kotlin) 


* 
[PHP](https://github.com/starfederation/datastar-php)  (plus [Craft CMS](https://putyourlightson.com/plugins/datastar) and [Laravel](https://github.com/putyourlightson/laravel-datastar))


* 
[Python](https://github.com/starfederation/datastar-python) 


* 
[Ruby](https://github.com/starfederation/datastar-ruby) 


* 
[Rust](https://github.com/starfederation/datastar-rust)  (plus [Rama](https://ramaproxy.org/docs/rama/http/sse/datastar/index.html))


* 
[TypeScript](https://github.com/starfederation/datastar-typescript)  (plus [PocketPages](https://github.com/benallfree/pocketpages/tree/main/packages/plugins/datastar))



---

# Security

Datastar expressions are strings that are evaluated in a sandboxed context. 

* 
**Escape User Input**: Always escape user input to prevent XSS. 


* 
**Avoid Sensitive Data**: Avoid leaking sensitive data in signals. 


* 
**Ignore Unsafe Input**: Use `data-ignore` if you cannot escape input. 


* 
**CSP**: `unsafe-eval` must be allowed for scripts in Content Security Policy.

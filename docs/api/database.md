
# Realtime Database

Firestack mimics the [Web Firebase SDK Realtime Database](https://firebase.google.com/docs/database/web/read-and-write), whilst
providing support for devices in low/no data connection state.

All Realtime Database operations are accessed via `database()`.

Basic read example:
```javascript
firestack.database()
  .ref('posts')
  .on('value', (snapshot) => {
    const value = snapshot.val();     
  });
```

Read for export:
```javascript
firestack.database()
  .ref('posts')
  .on('value', (snapshot) => {
    const value = snapshot.exportVal();     
  });
```
This includes hidden properties like `.priority`

Basic write example:
```javascript
firestack.database()
  .ref('posts/1234')
  .set({
    title: 'My awesome post',
    content: 'Some awesome content',   
  });
```

Test value exists at location:
```javascript
firestack.database()
  .ref('posts/1234')
  .on('value', (snapshot) => {
    const exists = snapshot.exists();
  });
```

Basic write with priority example:
```javascript
firestack.database()
  .ref('posts/1235')
  .setWithPriority({
    title: 'Another Awesome Post',
    content: 'Some awesome content',
  }, 10);
```
Useful for `orderByPriority` queries.


Transaction Support:
```javascript
firestack.database()
  .ref('posts/1234/title')
  .transaction((title) => 'My Awesome Post');
```

## Unmounted components

Listening to database updates on unmounted components will trigger a warning:

> Can only update a mounted or mounting component. This usually means you called setState() on an unmounted component. This is a no-op. Please check the code for the undefined component.

It is important to always unsubscribe the reference from receiving new updates once the component is no longer in use.
This can be achived easily using [Reacts Component Lifecycle](https://facebook.github.io/react/docs/react-component.html#the-component-lifecycle) events:

Always ensure the handler function provided is of the same reference so Firestack can unsubscribe the ref listener.

```javascript
class MyComponent extends Component {
  constructor() {
    super();
    this.ref = null;
  }

  // On mount, subscribe to ref updates
  componentDidMount() {
    this.ref = firestack.database().ref('posts/1234');
    this.ref.on('value', this.handlePostUpdate);
  }

  // On unmount, ensure we no longer listen for updates
  componentWillUnmount() {
    if (this.ref) {
      this.ref.off('value', this.handlePostUpdate);
    }
  }

  // Bind the method only once to keep the same reference
  handlePostUpdate = (snapshot) => {
    console.log('Post Content', snapshot.val());
  }

  render() {
    return null;
  }
}

```

## Usage in offline environments

### Reading data

Firstack allows the database instance to [persist on disk](https://firebase.google.com/docs/database/android/offline-capabilities) if enabled.
To enable database persistence, call the following method before calls are made:

```javascript
firestack.database().setPersistence(true);
```

Any subsequent calls to Firebase stores the data for the ref on disk.

### Writing data

Out of the box, Firebase has great support for writing operations in offline environments. Calling a write command whilst offline
will always trigger any subscribed refs with new data. Once the device reconnects to Firebase, it will be synced with the server.

The following todo code snippet will work in both online and offline environments:

```javascript
// Assume the todos are stored as an object value on Firebase as:
// { name: string, complete: boolean }

class ToDos extends Component {
  constructor() {
    super();
    this.ref = null;
    this.listView = new ListView.DataSource({
      rowHasChanged: (r1, r2) => r1 !== r2,
    });

    this.state = {
      todos: this.listView.cloneWithRows({}),             
    };
    
    // Keep a local reference of the TODO items
    this.todos = {};
  }

  // Load the Todos on mount
  componentDidMount() {
    this.ref = firestack.database().ref('users/1234/todos');
    this.ref.on('value', this.handleToDoUpdate);
  }

  // Unsubscribe from the todos on unmount
  componentWillUnmount() {
    if (this.ref) {
      this.ref.off('value', this.handleToDoUpdate);
    }
  }

  // Handle ToDo updates
  handleToDoUpdate = (snapshot) => {
    this.todos = snapshot.val() || {};

    this.setState({
      todos: this.listView.cloneWithRows(this.todos),       
    });
  }

  // Add a new ToDo onto Firebase
  // If offline, this will still trigger an update to handleToDoUpdate
  addToDo() {
    firestack.database()
      .ref('users/1234/todos')
      .set({
        ...this.todos, {
           name: 'Yet another todo...',
           complete: false,
        },
      });
  }

  // Render a ToDo row
  renderToDo(todo) {
    // Dont render the todo if its complete
    if (todo.complete) {
      return null;
    }

    return (
      <View>
        <Text>{todo.name}</Text>
      </View>
    );
  }
  
  // Render the list of ToDos with a Button
  render() {
    return (
      <View>
        <ListView
          dataSource={this.state.todos}
          renderRow={(...args) => this.renderToDo(...args)}
        />
            
        <Button
          title={'Add ToDo'}
          onPress={() => this.addToDo}
        />
      <View>
    );
  }
```

#### Differences between `.on` & `.once`

With persistence enabled, any calls to a ref with `.once` will always read the data from disk and not contact the server.
On behavious differently, by first checking for a connection and if none exists returns the persisted data. If it successfully connects
to the server, the new data will be returned and the disk data will be updated.

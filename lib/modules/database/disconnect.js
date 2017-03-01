/* @flow */

import { NativeModules } from 'react-native';
import { promisify } from './../../utils';
import Reference from './reference';

const FirestackDatabase = NativeModules.FirestackDatabase;

/**
 * @class Disconnect
 */
export default class Disconnect {
  ref: Reference;

  constructor(ref: Reference) {
    this.ref = ref;
  }

  setValue(val: string | Object) {
    const path = this.ref._dbPath();
    if (typeof val === 'string') {
      return promisify('onDisconnectSetString', FirestackDatabase)(path, val);
    } else if (typeof val === 'object') {
      return promisify('onDisconnectSetObject', FirestackDatabase)(path, val);
    }
  }

  remove() {
    return promisify('onDisconnectRemove', FirestackDatabase)(this.ref._dbPath());
  }

  cancel() {
    return promisify('onDisconnectCancel', FirestackDatabase)(this.ref._dbPath());
  }
}

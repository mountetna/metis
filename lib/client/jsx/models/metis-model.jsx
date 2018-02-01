import * as Redux from 'redux';
import * as ReduxLogger from 'redux-logger';
import fileData from './metis-reducer';
import JanusLogReducer from './janus-log-reducer';
import LastActionReducer from './last-action-reducer';

export default class MetisModel{

  constructor() {

    var janusLogReducer = new JanusLogReducer();
    var lastAction = new LastActionReducer();
    var reducer = Redux.combineReducers({
      fileData,
      'userInfo': janusLogReducer.reducer(),
      'lastAction': lastAction.reducer()
    });

    var defaultState = {

      'fileData': {

        'fileList': [],
        'fileUploads': [],
        'fileFails': []
      },

      'userInfo': {

        'userId': null,
        'userEmail': '',
        'authToken': '',
        'firstName': '',
        'lastName': '',
        'permissions': [],

        'masterPerms': false,

        'loginStatus': false,
        'loginError': false,
        'loginErrorMsg': 'Invalid sign in.'
      }
    };

    let middleWares = []
    if(process.env.NODE_ENV != 'production') middleWares.push(ReduxLogger.createLogger());

    this.store = Redux.applyMiddleware(...middleWares)(Redux.createStore)(reducer, defaultState);
  }
}

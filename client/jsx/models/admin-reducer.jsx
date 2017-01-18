export default class AdminReducer{

  reducer(){

    return (state = {}, action)=>{

      switch(action['type']){

        case 'HAS_PERMISSIONS':

          var adminInfo = Object.assign({}, state);
          adminInfo['permissions'] = this.camelCaseIt(action['data']);

          // Generate some random id's for react keys.
          for(var a = 0; a < adminInfo['permissions']['length']; ++a){

            adminInfo['permissions'][a]['reactKey'] = GENERATE_RAND_KEY();
            adminInfo['permissions'][a]['persisted'] = true;
          }

          return adminInfo;

        case 'ADD_PERMISSION':

          var adminInfo = Object.assign({}, state);

          var randKey = GENERATE_RAND_KEY();
          var newPermission = {

            'id': null,
            'projectId': null,
            'projectName': '',
            'role': '',
            'userEmail': '',
            'userId': null,
            'reactKey': randKey,
            'persisted': false
          };

          adminInfo['permissions'].unshift(newPermission);
          return adminInfo;

        case 'REMOVE_UNSAVED_PERMISSION':

          var nextState = Object.assign({}, state);

          /*
           * Need to check if the item is persisted or not!
           * If so then we need to delete it from the DB.
           * In fact we should probably move this into the JS controller.
           * That way we just delete the entry from the server and return the
           * updated list.
           */

          for(var a = 0; a < nextState['permissions']['length']; ++a){

            if(nextState['permissions'][a]['reactKey'] == action['reactKey']){

              nextState['permissions'].splice(a, 1);
            }
          }
          return nextState;

        case 'SAVE_PERMISSIONS':

          var nextState = Object.assign({}, state);
          return nextState;

        case 'HAS_USERS':

          var adminInfo = Object.assign({}, state);
          adminInfo['users'] = this.camelCaseIt(action['data']);
          return adminInfo;

        case 'HAS_PROJECTS':

          var adminInfo = Object.assign({}, state);
          adminInfo['projects'] = this.camelCaseIt(action['data']);
          return adminInfo;
          
        default:

          var nextState = Object.assign({}, state);
          return nextState;
      }
    };
  }

  camelCaseIt(object){

    for(var index in object){

      for(var key in object[index]){

        object[index][CAMEL_CASE_IT(key)] = object[index][key];
        if(key.indexOf('_') != -1) delete object[index][key];
      }
    }

    return object;
  }
}
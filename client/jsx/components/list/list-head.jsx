import * as React from 'react'

export default class ListHead extends React.Component{

  constructor(){

    super();
  }

  selectFile(){

    /*
     * We are using a button to surragate the file input so we may have 
     * a custom browse button.
     */
    document.getElementById('file-selector').click();
  }

  fileSelected(event){

    if(event === undefined) return;
    var fileSelector = event.target;
    var file = fileSelector.files[0];
    this['props'].fileSelected(file);
  }

  render(){

    return (  

      <div id='list-head-group'>


          <div className='list-head-title'>

            { 'type' }
          </div>
          <div className='list-head-title'>

            { 'file name' }
          </div>
          <div className='list-head-title'>

            { 'project' }
          </div>
          <div className='list-head-title'>

            { 'size' }
          </div>
        <input id='file-selector' type='file' name='upload-file' onChange={ this['fileSelected'].bind(this) } />
        <button id='file-select-btn' onClick={ this['selectFile'].bind(this) }>

          <span className='glyphicon glyphicon-plus white-glyphicon'></span>
          { ' ADD FILE' }
        </button>
      </div>
    );
  }
}
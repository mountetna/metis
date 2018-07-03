import * as React from 'react';
import { connect } from 'react-redux';
import { selectCurrentFolder } from '../selectors/directory-selector';

// this is the Metis control bar, which contains basic operations
// like 'upload file' and 'create folder'

const ControlButton = ({onClick, icon, title}) => {
  return <button className='control-btn' onClick={ onClick } title={ title }>
    {
      Array.isArray(icon) ?
        <span className='fa-stack fa-fw'>
          <i className={ `fa fa-stack-2x fa-${icon[0]}` }/>
          <i className={ `fa fa-stack-1x fa-${icon[1]} white-icon` }/>
        </span>
      :
        <span className='fa-stack fa-fw'>
          <i className={ `fa fa-fw fa-2x fa-${icon}` }/>
        </span>
    }
  </button>
}

class ControlBar extends React.Component {
  selectFolder(){
    let { current_folder } = this.props;

    let folder_name = prompt("Enter the folder name", "Untitled Folder");
    if (!folder_name) return;
    this.props.createFolder(folder_name, current_folder);
  }

  selectFile() {
    this.input.click();
  }

  fileSelected(event){
    let { current_folder, fileSelected } = this.props;

    if(event === undefined) return;

    fileSelected( this.input.files[0], current_folder );

    // Reset the input field.
    this.input.value = '';
  }

  setInputRef(input) {
    this.input = input;
  }


  render() {
    let fileSelector = {
      style: { display: 'none' },
      type: 'file',
      name: 'upload-file',
      ref: this.setInputRef.bind(this),
      onChange: this.fileSelected.bind(this)
    };

    return (
      <div id='control-bar'>
        <input { ...fileSelector } />
        <ControlButton onClick={ this.selectFolder.bind(this) } title='Create folder' icon={ [ 'folder', 'plus' ] }/>
        <ControlButton onClick={ this.selectFile.bind(this) } title='Upload file' icon='upload'/>
      </div>
    );
  }
}

export default connect(
  // map state
  (state) => ({current_folder: selectCurrentFolder(state)}),

  (dispatch) => ({
    fileSelected: (file, folder_name)=>dispatch({ type: 'FILE_SELECTED', file, folder_name }),
    createFolder: (folder_name, parent_folder)=>dispatch({ type: 'CREATE_FOLDER', folder_name, parent_folder })
  })
)(ControlBar);
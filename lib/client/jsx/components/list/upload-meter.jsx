import * as React from 'react';
import { byteFormat } from '../../utils/format';

export default class UploadMeter extends React.Component{
  constructor(){
    super();
  }

  calcUploadPercent(){
    let { upload } = this.props;
    let { file_size, current_byte_position } = upload;

    if (file_size == 0) {
      return { width: '0%' };
    }
    else {
      return { width: String((current_byte_position/file_size)*100) + '%' };
    }
  }

  parseUploadBytes(){
    let { upload } = this.props;
    let { file_size, current_byte_position } = upload;

    file_size = byteFormat(file_size, true);
    let bytesUploaded = byteFormat(current_byte_position, true);

    let uploadInfoProps = {
      className: 'upload-meter-info light-text',
      style: { float: 'left' }
    }

    let bytesUploadedProps = {
      className: 'dark-text',
      style: { fontWeight: 900 },
      title: 'kiloBYTES uploaded.'
    }

    return (
      <div { ...uploadInfoProps }>
          <span { ...bytesUploadedProps }>
            { bytesUploaded }
          </span>
          { ` of ${file_size} uploaded`}
      </div>
    );
  }

  parseUploadSpeed(){
    let { upload } = this.props;
    let { paused, upload_speed } = upload;

    if (upload_speed && !paused) {
      if (isNaN(upload_speed)) return '';

      let speed = byteFormat(upload_speed, 1024, true);

      let bitSpeedProps = {
        className: 'dark-text',
        style: { fontWeight: 900 },
        title: 'kiloBITS per second.'
      }

      return (
        <div className='upload-meter-info' style={{ float: 'right' }}>
          <span { ...bitSpeedProps }>
            { speed }
          </span>
        </div>
      );
    }
    else {
      return '';
    }
  }

  render(){
    return (
      <td className='upload-meter-group'>
        <div className='upload-meter-tray'>
          <div className='upload-meter-bar' style={ this.calcUploadPercent() }>
          </div>
        </div>

        { this.parseUploadBytes() }
        { this.parseUploadSpeed() }
      </td>
    );
  }
}

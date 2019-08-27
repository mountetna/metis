import { headers, parseJSON, checkStatus, json_post } from '../utils/fetch';

export const postAuthorizeUpload = (project_name, bucket_name, file_path) => {
  let request = { project_name, file_path, bucket_name };

  return json_post('/authorize/upload', request)
}

const postUpload = (upload_url, request) => {
  return fetch(upload_url,
  {
    method: 'POST',
    credentials: 'same-origin',
    headers: headers('json'),
    body: JSON.stringify(request)
  })
}

export const postUploadStart = (upload_url, request) => {
  return postUpload(upload_url, { ...request, action: 'start' }).then(checkStatus).then(parseJSON);
}

export const postUploadCancel = (upload_url, request) => {
  return postUpload(upload_url, { ...request, action: 'cancel' }).then(checkStatus);
}

export const postUploadBlob = (upload_url, request) => {
  let form = new FormData();

  form.append('action', 'blob');
  Object.keys(request).forEach(key => form.append(key, request[key]));

  return fetch(upload_url,
  {
    method: 'POST',
    credentials: 'same-origin',
    body: form
  }).then(checkStatus).then(parseJSON);
}

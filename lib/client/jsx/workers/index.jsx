import work from 'webworkify-webpack'

const maxWorkers = window.navigator.hardwareConcurrency || 4;

// keep track of workers in use
let workerMap = new Map();

export function createWorker(script) {
  if (workerMap.size === maxWorkers) {
    throw `too many workers max: ${maxWorkers} - make sure to clean them up with terminateWorker`;
  }
  let worker = work(script);
  workerMap.set(worker, true);

  return worker;
}

export function terminateWorker(worker) {
  worker.addEventListener('message', () => {});
  worker.terminate();
  workerMap.delete(worker);
}

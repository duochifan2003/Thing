export function createSaveQueue(write) {
  let tail = Promise.resolve();
  return (value) => {
    const job = tail.catch(() => undefined).then(() => write(value));
    tail = job;
    return job;
  };
}

.pragma library

function shuffle(values) {
    const result = values.slice();
    for (let i = result.length - 1; i > 0; i--) {
        const j = Math.floor(Math.random() * (i + 1));
        const value = result[i];
        result[i] = result[j];
        result[j] = value;
    }
    return result;
}

function rotate(values, start) {
    return values.slice(start).concat(values.slice(0, start));
}

function create(values, sequenceIndex, previousLast, shuffled) {
    const pool = values.slice();
    if (pool.length === 0)
        return [];

    if (shuffled) {
        if (previousLast === null || previousLast === undefined || previousLast < 0)
            return shuffle(pool);

        const previousIndex = pool.indexOf(previousLast);
        const firstIndex = previousIndex < 0 ? 0 : (previousIndex + 1) % pool.length;
        const first = pool[firstIndex];
        return [first].concat(shuffle(pool.filter(shape => shape !== first)));
    }

    let start = ((sequenceIndex % pool.length) + pool.length) % pool.length;
    let result = rotate(pool, start);
    if (previousLast !== null && previousLast !== undefined && previousLast >= 0 && result[0] === previousLast) {
        start = (start + 1) % pool.length;
        result = rotate(pool, start);
    }
    return result;
}

"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.execute = exports.inputParameters = exports.supportedEndpoints = void 0;
const tslib_1 = require("tslib");
const ea_bootstrap_1 = require("@chainlink/ea-bootstrap");
const fs = tslib_1.__importStar(require("fs"));
const path_1 = tslib_1.__importDefault(require("path"));
const ethers_1 = require("ethers");
// This should be filled in with a lowercase name corresponding to the API endpoint
exports.supportedEndpoints = ['compound'];
// export interface ResponseSchema {
//   data: {
//     // Some data
//   }
// }
exports.inputParameters = {
    chain: true,
    network: true,
    cusdc: true,
};
const execute = async (request, _, config) => {
    /**
     * Testing with
     * curl -d '{"id": 0, "data": {"chain": "eth", "network": "kovan", "cusdc": "0x4a92E71227D294F041BD82dd8f78591B75140d63"}}'\
              -H "Content-Type: application/json" -X POST http://localhost:8080/
     */
    const validator = new ea_bootstrap_1.Validator(request, exports.inputParameters);
    if (validator.error)
        throw validator.error;
    const jobRunID = validator.validated.id;
    const { chain, network, cusdc } = validator.validated.data;
    if (!['eth', 'polygon'].includes(chain))
        throw new ea_bootstrap_1.AdapterError({ jobRunID, statusCode: 400, message: 'Chain must be eth or polygon' });
    if (chain == 'eth' && !['mainnet', 'kovan'].includes(network))
        throw new ea_bootstrap_1.AdapterError({ jobRunID, statusCode: 400, message: `Bad network ${network}` });
    if (chain == 'polygon' && !['mainnet', 'mumbai'].includes(network))
        throw new ea_bootstrap_1.AdapterError({ jobRunID, statusCode: 400, message: `Bad network ${network}` });
    // TODO: catch errors here
    const result = await getTokenInfo(chain, network, cusdc, config.apiKey || 'foo');
    return {
        jobRunID,
        result,
        data: {
            result,
        },
        statusCode: 200,
    };
};
exports.execute = execute;
const getTokenInfo = async (chain, network, cusdc, apiKey) => {
    // TODO: get different addresses based on network
    const provider = new ethers_1.ethers.providers.JsonRpcProvider(`https://kovan.infura.io/v3/${apiKey}`);
    console.log({ chain, network });
    const abi = fs.readFileSync(path_1.default.resolve(__dirname, '../../src/abi/cUSDC.json'), 'utf8');
    const cusdcContract = new ethers_1.ethers.Contract(cusdc, abi, provider);
    return cusdcContract.exchangeRateStored();
};
//# sourceMappingURL=data:application/json;base64,eyJ2ZXJzaW9uIjozLCJmaWxlIjoiY29tcG91bmQuanMiLCJzb3VyY2VSb290IjoiIiwic291cmNlcyI6WyIuLi8uLi9zcmMvZW5kcG9pbnQvY29tcG91bmQudHMiXSwibmFtZXMiOltdLCJtYXBwaW5ncyI6Ijs7OztBQUFBLDBEQUFpRTtBQUdqRSwrQ0FBd0I7QUFDeEIsd0RBQXVCO0FBQ3ZCLG1DQUErQjtBQUUvQixtRkFBbUY7QUFDdEUsUUFBQSxrQkFBa0IsR0FBRyxDQUFDLFVBQVUsQ0FBQyxDQUFBO0FBRTlDLG9DQUFvQztBQUNwQyxZQUFZO0FBQ1osbUJBQW1CO0FBQ25CLE1BQU07QUFDTixJQUFJO0FBRVMsUUFBQSxlQUFlLEdBQW9CO0lBQzlDLEtBQUssRUFBRSxJQUFJO0lBQ1gsT0FBTyxFQUFFLElBQUk7SUFDYixLQUFLLEVBQUUsSUFBSTtDQUNaLENBQUE7QUFFTSxNQUFNLE9BQU8sR0FBOEIsS0FBSyxFQUFFLE9BQU8sRUFBRSxDQUFDLEVBQUUsTUFBTSxFQUFFLEVBQUU7SUFDN0U7Ozs7T0FJRztJQUNILE1BQU0sU0FBUyxHQUFHLElBQUksd0JBQVMsQ0FBQyxPQUFPLEVBQUUsdUJBQWUsQ0FBQyxDQUFBO0lBQ3pELElBQUksU0FBUyxDQUFDLEtBQUs7UUFBRSxNQUFNLFNBQVMsQ0FBQyxLQUFLLENBQUE7SUFFMUMsTUFBTSxRQUFRLEdBQUcsU0FBUyxDQUFDLFNBQVMsQ0FBQyxFQUFFLENBQUE7SUFDdkMsTUFBTSxFQUFFLEtBQUssRUFBRSxPQUFPLEVBQUUsS0FBSyxFQUFFLEdBQUcsU0FBUyxDQUFDLFNBQVMsQ0FBQyxJQUFJLENBQUE7SUFFMUQsSUFBSSxDQUFDLENBQUMsS0FBSyxFQUFFLFNBQVMsQ0FBQyxDQUFDLFFBQVEsQ0FBQyxLQUFLLENBQUM7UUFDckMsTUFBTSxJQUFJLDJCQUFZLENBQUMsRUFBRSxRQUFRLEVBQUUsVUFBVSxFQUFFLEdBQUcsRUFBRSxPQUFPLEVBQUUsOEJBQThCLEVBQUUsQ0FBQyxDQUFBO0lBRWhHLElBQUksS0FBSyxJQUFJLEtBQUssSUFBSSxDQUFDLENBQUMsU0FBUyxFQUFFLE9BQU8sQ0FBQyxDQUFDLFFBQVEsQ0FBQyxPQUFPLENBQUM7UUFDM0QsTUFBTSxJQUFJLDJCQUFZLENBQUMsRUFBRSxRQUFRLEVBQUUsVUFBVSxFQUFFLEdBQUcsRUFBRSxPQUFPLEVBQUUsZUFBZSxPQUFPLEVBQUUsRUFBRSxDQUFDLENBQUE7SUFDMUYsSUFBSSxLQUFLLElBQUksU0FBUyxJQUFJLENBQUMsQ0FBQyxTQUFTLEVBQUUsUUFBUSxDQUFDLENBQUMsUUFBUSxDQUFDLE9BQU8sQ0FBQztRQUNoRSxNQUFNLElBQUksMkJBQVksQ0FBQyxFQUFFLFFBQVEsRUFBRSxVQUFVLEVBQUUsR0FBRyxFQUFFLE9BQU8sRUFBRSxlQUFlLE9BQU8sRUFBRSxFQUFFLENBQUMsQ0FBQTtJQUUxRiwwQkFBMEI7SUFDMUIsTUFBTSxNQUFNLEdBQUcsTUFBTSxZQUFZLENBQUMsS0FBSyxFQUFFLE9BQU8sRUFBRSxLQUFLLEVBQUUsTUFBTSxDQUFDLE1BQU0sSUFBSSxLQUFLLENBQUMsQ0FBQTtJQUVoRixPQUFPO1FBQ0wsUUFBUTtRQUNSLE1BQU07UUFDTixJQUFJLEVBQUU7WUFDSixNQUFNO1NBQ1A7UUFDRCxVQUFVLEVBQUUsR0FBRztLQUNoQixDQUFBO0FBQ0gsQ0FBQyxDQUFBO0FBL0JZLFFBQUEsT0FBTyxXQStCbkI7QUFFRCxNQUFNLFlBQVksR0FBRyxLQUFLLEVBQ3hCLEtBQWEsRUFDYixPQUFlLEVBQ2YsS0FBYSxFQUNiLE1BQWMsRUFDRyxFQUFFO0lBQ25CLGlEQUFpRDtJQUNqRCxNQUFNLFFBQVEsR0FBRyxJQUFJLGVBQU0sQ0FBQyxTQUFTLENBQUMsZUFBZSxDQUFDLDhCQUE4QixNQUFNLEVBQUUsQ0FBQyxDQUFBO0lBRTdGLE9BQU8sQ0FBQyxHQUFHLENBQUMsRUFBRSxLQUFLLEVBQUUsT0FBTyxFQUFFLENBQUMsQ0FBQTtJQUUvQixNQUFNLEdBQUcsR0FBRyxFQUFFLENBQUMsWUFBWSxDQUFDLGNBQUksQ0FBQyxPQUFPLENBQUMsU0FBUyxFQUFFLDBCQUEwQixDQUFDLEVBQUUsTUFBTSxDQUFDLENBQUE7SUFDeEYsTUFBTSxhQUFhLEdBQUcsSUFBSSxlQUFNLENBQUMsUUFBUSxDQUFDLEtBQUssRUFBRSxHQUFHLEVBQUUsUUFBUSxDQUFDLENBQUE7SUFFL0QsT0FBTyxhQUFhLENBQUMsa0JBQWtCLEVBQUUsQ0FBQTtBQUMzQyxDQUFDLENBQUEiLCJzb3VyY2VzQ29udGVudCI6WyJpbXBvcnQgeyBBZGFwdGVyRXJyb3IsIFZhbGlkYXRvciB9IGZyb20gJ0BjaGFpbmxpbmsvZWEtYm9vdHN0cmFwJ1xuaW1wb3J0IHsgQ29uZmlnLCBFeGVjdXRlV2l0aENvbmZpZywgSW5wdXRQYXJhbWV0ZXJzIH0gZnJvbSAnQGNoYWlubGluay90eXBlcydcblxuaW1wb3J0ICogYXMgZnMgZnJvbSAnZnMnXG5pbXBvcnQgcGF0aCBmcm9tICdwYXRoJ1xuaW1wb3J0IHsgZXRoZXJzIH0gZnJvbSAnZXRoZXJzJ1xuXG4vLyBUaGlzIHNob3VsZCBiZSBmaWxsZWQgaW4gd2l0aCBhIGxvd2VyY2FzZSBuYW1lIGNvcnJlc3BvbmRpbmcgdG8gdGhlIEFQSSBlbmRwb2ludFxuZXhwb3J0IGNvbnN0IHN1cHBvcnRlZEVuZHBvaW50cyA9IFsnY29tcG91bmQnXVxuXG4vLyBleHBvcnQgaW50ZXJmYWNlIFJlc3BvbnNlU2NoZW1hIHtcbi8vICAgZGF0YToge1xuLy8gICAgIC8vIFNvbWUgZGF0YVxuLy8gICB9XG4vLyB9XG5cbmV4cG9ydCBjb25zdCBpbnB1dFBhcmFtZXRlcnM6IElucHV0UGFyYW1ldGVycyA9IHtcbiAgY2hhaW46IHRydWUsXG4gIG5ldHdvcms6IHRydWUsXG4gIGN1c2RjOiB0cnVlLFxufVxuXG5leHBvcnQgY29uc3QgZXhlY3V0ZTogRXhlY3V0ZVdpdGhDb25maWc8Q29uZmlnPiA9IGFzeW5jIChyZXF1ZXN0LCBfLCBjb25maWcpID0+IHtcbiAgLyoqXG4gICAqIFRlc3Rpbmcgd2l0aCBcbiAgICogY3VybCAtZCAne1wiaWRcIjogMCwgXCJkYXRhXCI6IHtcImNoYWluXCI6IFwiZXRoXCIsIFwibmV0d29ya1wiOiBcImtvdmFuXCIsIFwiY3VzZGNcIjogXCIweDRhOTJFNzEyMjdEMjk0RjA0MUJEODJkZDhmNzg1OTFCNzUxNDBkNjNcIn19J1xcXG4gICAgICAgICAgICAtSCBcIkNvbnRlbnQtVHlwZTogYXBwbGljYXRpb24vanNvblwiIC1YIFBPU1QgaHR0cDovL2xvY2FsaG9zdDo4MDgwL1xuICAgKi9cbiAgY29uc3QgdmFsaWRhdG9yID0gbmV3IFZhbGlkYXRvcihyZXF1ZXN0LCBpbnB1dFBhcmFtZXRlcnMpXG4gIGlmICh2YWxpZGF0b3IuZXJyb3IpIHRocm93IHZhbGlkYXRvci5lcnJvclxuXG4gIGNvbnN0IGpvYlJ1bklEID0gdmFsaWRhdG9yLnZhbGlkYXRlZC5pZFxuICBjb25zdCB7IGNoYWluLCBuZXR3b3JrLCBjdXNkYyB9ID0gdmFsaWRhdG9yLnZhbGlkYXRlZC5kYXRhXG5cbiAgaWYgKCFbJ2V0aCcsICdwb2x5Z29uJ10uaW5jbHVkZXMoY2hhaW4pKVxuICAgIHRocm93IG5ldyBBZGFwdGVyRXJyb3IoeyBqb2JSdW5JRCwgc3RhdHVzQ29kZTogNDAwLCBtZXNzYWdlOiAnQ2hhaW4gbXVzdCBiZSBldGggb3IgcG9seWdvbicgfSlcblxuICBpZiAoY2hhaW4gPT0gJ2V0aCcgJiYgIVsnbWFpbm5ldCcsICdrb3ZhbiddLmluY2x1ZGVzKG5ldHdvcmspKVxuICAgIHRocm93IG5ldyBBZGFwdGVyRXJyb3IoeyBqb2JSdW5JRCwgc3RhdHVzQ29kZTogNDAwLCBtZXNzYWdlOiBgQmFkIG5ldHdvcmsgJHtuZXR3b3JrfWAgfSlcbiAgaWYgKGNoYWluID09ICdwb2x5Z29uJyAmJiAhWydtYWlubmV0JywgJ211bWJhaSddLmluY2x1ZGVzKG5ldHdvcmspKVxuICAgIHRocm93IG5ldyBBZGFwdGVyRXJyb3IoeyBqb2JSdW5JRCwgc3RhdHVzQ29kZTogNDAwLCBtZXNzYWdlOiBgQmFkIG5ldHdvcmsgJHtuZXR3b3JrfWAgfSlcblxuICAvLyBUT0RPOiBjYXRjaCBlcnJvcnMgaGVyZVxuICBjb25zdCByZXN1bHQgPSBhd2FpdCBnZXRUb2tlbkluZm8oY2hhaW4sIG5ldHdvcmssIGN1c2RjLCBjb25maWcuYXBpS2V5IHx8ICdmb28nKVxuXG4gIHJldHVybiB7XG4gICAgam9iUnVuSUQsXG4gICAgcmVzdWx0LFxuICAgIGRhdGE6IHtcbiAgICAgIHJlc3VsdCxcbiAgICB9LFxuICAgIHN0YXR1c0NvZGU6IDIwMCxcbiAgfVxufVxuXG5jb25zdCBnZXRUb2tlbkluZm8gPSBhc3luYyAoXG4gIGNoYWluOiBzdHJpbmcsXG4gIG5ldHdvcms6IHN0cmluZyxcbiAgY3VzZGM6IHN0cmluZyxcbiAgYXBpS2V5OiBzdHJpbmcsXG4pOiBQcm9taXNlPHN0cmluZz4gPT4ge1xuICAvLyBUT0RPOiBnZXQgZGlmZmVyZW50IGFkZHJlc3NlcyBiYXNlZCBvbiBuZXR3b3JrXG4gIGNvbnN0IHByb3ZpZGVyID0gbmV3IGV0aGVycy5wcm92aWRlcnMuSnNvblJwY1Byb3ZpZGVyKGBodHRwczovL2tvdmFuLmluZnVyYS5pby92My8ke2FwaUtleX1gKVxuXG4gIGNvbnNvbGUubG9nKHsgY2hhaW4sIG5ldHdvcmsgfSlcblxuICBjb25zdCBhYmkgPSBmcy5yZWFkRmlsZVN5bmMocGF0aC5yZXNvbHZlKF9fZGlybmFtZSwgJy4uLy4uL3NyYy9hYmkvY1VTREMuanNvbicpLCAndXRmOCcpXG4gIGNvbnN0IGN1c2RjQ29udHJhY3QgPSBuZXcgZXRoZXJzLkNvbnRyYWN0KGN1c2RjLCBhYmksIHByb3ZpZGVyKVxuXG4gIHJldHVybiBjdXNkY0NvbnRyYWN0LmV4Y2hhbmdlUmF0ZVN0b3JlZCgpXG59XG4iXX0=
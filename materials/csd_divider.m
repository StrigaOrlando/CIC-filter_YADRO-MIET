function c = csd_divider(D, maxError)
%CSD_DIVIDER Constant reciprocal as a CSD shift/add network.
% c = csd_divider(D,maxError), default maxError=1e-3 (relative error).
% Search F=0,...,100 for abs((K/2^F)/(1/D) - 1) < maxError.
% Returns c.numTerms, c.signs, c.powers.
% Approximation: 1/D ~= sum(c.signs .* 2.^c.powers).
% Comparison uses double arithmetic; equality does not satisfy it.
if nargin < 2, maxError = 1e-3; end
validateattributes(D, {'numeric'}, {'real','finite','scalar','nonzero'});
validateattributes(maxError, {'numeric'}, {'real','finite','scalar','positive'});
D = double(D); maxError = double(maxError);
target = 1/D;
if ~isfinite(target)
    error('csd:Range','Reciprocal is outside the finite double range.');
end
maxFracBits = 100;
found = false;
for F = 0:maxFracBits
    K = floor(2^F / D);
    if ~isfinite(K) || abs(K) > 2^40
        error('csd:Range', ...
            'Required coefficient exceeds abs(K)<=2^40; increase maxError.');
    end
    coefficientError = K/2^F / target - 1;
    if abs(coefficientError) < maxError
        found = true;
        break;
    end
end
if ~found
    error('csd:Precision', ...
        'Cannot achieve abs(error)<%.16g with F<=%d. Last abs(error)=%.16g.', ...
        maxError,maxFracBits,abs(coefficientError));
end
n = abs(K);
digits = zeros(1,42);
i = 1;
while n > 0
    if mod(n,2) == 1
        % An odd value gets +1 or -1 so the next digit is zero.
        digits(i) = 2 - mod(n,4);
        n = n - digits(i);
    end
    n = n / 2;
    i = i + 1;
end
digits = sign(K) * digits(1:max(1,i-1));
idx = find(digits ~= 0);
idx = fliplr(idx);
% Preserve the original calculations; restrict the public result at the end.
c.divisor = D;
c.fracBits = F;
c.maxError = maxError;
c.K = K;
c.digits = digits;
c.shifts = idx - 1;
c.signs = digits(idx);
c.powers = c.shifts - F;
c.reciprocal = K / 2^F;
c.coefficientError = coefficientError;
c.absCoefficientError = abs(coefficientError);
c.numTerms = numel(idx);
c.numAddSub = max(0,c.numTerms - 1);
c.sumAbsWeights = sum(2.^c.shifts);
if c.numTerms == 0
    c.accumulatorExtraBits = 0;
else
    c.accumulatorExtraBits = ceil(log2(c.sumAbsWeights)) + 1;
end
symbols = repmat('0',size(digits));
symbols(digits == 1) = '+';
symbols(digits == -1) = '-';
c.csdInteger = fliplr(symbols);
parts = cell(1,c.numTerms);
for j = 1:c.numTerms
    parts{j} = sprintf('%+d*2^(%d)',c.signs(j),c.powers(j));
    if c.signs(j) == 1
        c.signs(j) = 0;
    else
        c.signs(j) = 1;
    end
end
c.expression = strjoin(parts,' ');
if c.numTerms == 0, c.expression = '0'; end

% Return data
c = struct('fracBits', c.fracBits, ...
           'numTerms', c.numTerms, ...
           'powers', c.powers, ...
           'signs', c.signs);
end

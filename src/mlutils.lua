local mlutils = {}

-- This code is mainly copied from https://github.com/koraykv/unsup/blob/master/kmeans.lua
-- with small modification to better suited our use case
--
-- The k-means algorithm.
--
--   > x: is supposed to be an MxN matrix, where M is the nb of samples and each sample is N-dim
--   > k: is the number of kernels
--   > niter: the number of iterations
--   > batchsize: the batch size [large is good, to parallelize matrix multiplications]
--   > callback: optional callback, at each iteration end
--   > verbose: prints a progress bar...
--
--   < returns the k means (centroids) + the counts per centroid
--
function mlutils.kmeans(x, k, niter, batchsize, callback, verbose)
   -- args
   local help = 'centroids,count = unsup.kmeans(Tensor(npoints,dim), k [, niter, batchsize, callback, verbose])'
   x = x or error('missing argument: ' .. help)
   k = k or error('missing argument: ' .. help)
   niter = niter or 1
   --batchsize = batchsize or math.min(1000, (#x)[1])
   batchsize = (#x)[1]

   -- resize data
   local k_size = x:size()
   k_size[1] = k
   if x:dim() > 2 then
      x = x:reshape(x:size(1), x:nElement()/x:size(1))
   end

   -- some shortcuts
   local sum = torch.sum
   local max = torch.max
   local pow = torch.pow

   -- dims
   local nsamples = (#x)[1]
   local ndims = (#x)[2]

   -- initialize means
   local myinit = true
   local centroids = nil
   local x2 = sum(pow(x,2),2)
   if myinit then
    centroids = x.new(k,ndims):zero()
    local min, max = x:min(1), x:max(1)  -- 1 x ndims
    for i = 1, k do
      if i > 1 then
        centroids[i]:copy(min + (max-min)/(k)*i)
      else
        centroids[i]:copy(min)
      end
    end
   else
    centroids = x.new(k,ndims):normal()
    for i = 1,k do
      centroids[i]:div(centroids[i]:norm())
    end
   end
   local totalcounts = x.new(k):zero()
   
   local losses = torch.Tensor(niter)   
   -- callback?
   --if callback then callback(0,centroids:reshape(k_size),totalcounts) end
   local val, labels, loss = nil, nil, 0
   -- do niter iterations
   for i = 1,niter do
      -- progress
      if verbose then xlua.progress(i,niter) end

      -- sums of squares
      local c2 = sum(pow(centroids,2),2)*0.5

      -- init some variables
      local summation = x.new(k,ndims):zero()
      local counts = x.new(k):zero()
      loss = 0

      -- process batch
      for i = 1,nsamples,batchsize do
         -- indices
         local lasti = math.min(i+batchsize-1,nsamples)
         local m = lasti - i + 1

         -- k-means step, on minibatch
         local batch = x[{ {i,lasti},{} }]
         local batch_t = batch:t()
         local tmp = centroids * batch_t
         for n = 1,(#batch)[1] do
            tmp[{ {},n }]:add(-1,c2)
         end
         val,labels = max(tmp,1)
         loss = loss + sum(x2[{ {i,lasti} }]*0.5 - val:t())

         -- count examplars per template
         local S = x.new(m,k):zero()
         for i = 1,(#labels)[2] do
            S[i][labels[1][i]] = 1
         end
         summation:add( S:t() * batch )
         counts:add( sum(S,1) )
      end
      print("loss", loss)      
      -- normalize
      for i = 1,k do
         if counts[i] ~= 0 then
            centroids[i] = summation[i]:div(counts[i])
         end
      end

      -- total counts
      totalcounts:add(counts)

      -- callback?
      if callback then 
        callback(centroids, loss)
         --local ret = callback(i,centroids:reshape(k_size),totalcounts) 
         --if ret then break end
      end
   end

   -- done
   return centroids:reshape(k_size),labels, totalcounts, loss
end

return mlutils

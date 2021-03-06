function [ posterior ] = calculate_posterior(X, Y, feedback, MODE, sparse_params, sparse_options)
% Calculate the posterior distribution given the observed data and user feedback
% Inputs:
% MODE          Feedback type: 1: noisy observation of weight. 2: binary relevance of feature
%               1: Multivariate Gaussian approximation of the posterior with spike and slab prior
%               2: Joint posterior approximation with EP.
% X             covariates (d x n)
% Y             response values
% feedback      values (1st column) and indices (2nd column) of feedback (n_feedbacks x 2)

    if MODE == 1
        %assume sparse prior (spike and slab) and approximate the posterior
        %with a multivariate Gaussian distribution using EP algorithm
        [fa, si, converged] = linreg_sns_ep(Y, X', sparse_params, sparse_options, feedback, [], sparse_options.si);
        if converged ~= 1
            disp(['linreg_sns_ep did not converge for MODE = ', num2str(MODE)])
        end
        posterior.si = si;
        posterior.fa = fa;
        %posterior.sigma = inv(fa.w.Tau);
        posterior.sigma = fa.w.Tau_chol' \ (fa.w.Tau_chol \ eye(size(fa.w.Tau_chol)));
        posterior.mean  = fa.w.Mean;
        posterior.p   = fa.gamma.p;
    end
    
    if MODE == 2        
        %assume sparse prior (spike and slab) and approximate the posterior with EP
        %weights are approximated by a multivariate Gaussian distribution.
        %latent variables are approximated by Bernoulli distribution. 
        if ~isempty(feedback)
            %remove the feedback that the user said "don't know"
            dont_know_fb = feedback(:,1)==-1;
            feedback(dont_know_fb,:) = [];
        end
        [fa, si, converged, subfuncs] = linreg_sns_ep(Y, X', sparse_params, sparse_options, [] , feedback, sparse_options.si);
        if converged ~= 1
            disp(['linreg_sns_ep did not converge for MODE = ', num2str(MODE)])
        end
        posterior.si = si;
        posterior.fa = fa;
        %posterior.sigma = inv(fa.w.Tau);
        posterior.sigma = fa.w.Tau_chol' \ (fa.w.Tau_chol \ eye(size(fa.w.Tau_chol))); % this should be faster than inv?
        posterior.mean  = fa.w.Mean;       
        posterior.p     = fa.gamma.p;
        posterior.ep_subfunctions = subfuncs;
        
    end
    
    %the following is the old model (not used anymore) 
    if MODE == 0
        %MODE 0: analytical solution for the posterior with multivariate Gaussian prior
        %calculate the analytical solution for posterior with Gaussian prior
        num_features = size(X,1);
        num_userfeedback = size(feedback,1);
        posterior = struct('mean',zeros(num_features,1), 'sigma', zeros(num_features,num_features));

        sigma_inverse = (1/sparse_params.tau2) * eye(num_features); % part 1

        X = X'; %design matrix
        sigma_inverse = sigma_inverse + (1/sparse_params.sigma2) * X'*X; %part 2 

        temp = 0;
        %if user has given feedback
        if num_userfeedback > 0
            F = feedback(:,1); % user feedbacks
            S = zeros(num_userfeedback, num_features); %design matrix for user feedback
            for i=1:num_userfeedback
                S(i,feedback(i,2)) = 1;
            end
            sigma_inverse = sigma_inverse + (1/sparse_params.eta2) * S'*S; %part 3
            temp = (1/sparse_params.eta2) * S'*F;
        end

        posterior.sigma = inv(sigma_inverse);
        posterior.mean  = posterior.sigma * ( (1/sparse_params.sigma2) * X'*Y + temp );
        %TODO: this posterior.si is required for the sparse case. fix the function interfaces later and remove this line
        posterior.si = [];
        posterior.p  = [];
    end  
end
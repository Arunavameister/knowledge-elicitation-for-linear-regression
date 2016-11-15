close all
clear all
% RNG_SEED = rng;

%% Load the proper dataset
%The following line loads X_all, Y_all
% load('DATA_Genome\mutation_outputs');
load('DATA_Genome\mutation_and_cyto_outputs');
drug_indices= [5  12  14  20  24  29  30  31  33  36  38  40];
drug_names = {'AZD2014','Dactolisib','Dexamethasone','Idelalisib','Methylprednisolone',...
    'PF.04691502','Pictilisib','Pimasertib','Refametinib','Temsirolimus','Trametinib','Venetoclax'};
Y_all = Y_all(:,drug_indices);

% X_all = X_all(:,3025:3032);
%% Parameters and data setup
MODE = 2; 
% MODE specifies the  type of feedback and the model that we are using
%           2: Feedback on relevance of features. Model: spike and slab prior

%data parameters
num_features       = size(X_all,2);
num_data           = size(X_all,1);        %all the data (test, train)
num_drugs          = size(Y_all,2);
num_trainingdata   = num_data-1;           %We use LOO cross validation

%model parameters based on CV results
% sparse_params  = struct('sigma2',1, 'tau2', 0.1^2 ,'rho', 0.3 );
sparse_params  = struct('sigma2',0.25, 'tau2', 1 ,'rho', 0.8 ); %This is based on LOO-CV results for all drugs and folds (it overfits I guess)
%(comment the following lines if you want to use the CV results)
% Let the algortihm learns the parameters 
% sparse_params.sigma2_prior = true;
% sparse_params.sigma2_a  = 1;
% sparse_params.sigma2_b  = 1;
% sparse_params.rho_prior = true;
% sparse_params.rho_a = 1;
% sparse_params.rho_b = 1;
model_params   = struct('Nu_y',sqrt(sparse_params.sigma2), 'Nu_theta', sqrt(sparse_params.tau2), ...
    'Nu_user', 0.1, 'P_user', 0.95, 'P_zero', sparse_params.rho, 'simulated_data', 0);
sparse_options = struct('damp',0.8, 'damp_decay',0.95, 'robust_updates',2, 'verbosity',0, ...
    'max_iter',1000, 'threshold',1e-5, 'min_site_prec',1e-6);
sparse_params.p_u = model_params.P_user;
sparse_params.eta2 = model_params.Nu_user^2;   % (NOT USED IN MODE=2)

%%Load the expert feedback
%Feedback = values (1st column) and indices (2nd column) of user feedback
Feedback = [];            %only used in experimental design methdos

%% Main algorithm
Y_hat_norm = zeros(num_drugs, num_data); %predicted values in normalized space
Y_hat_all  = zeros(num_drugs, num_data); %predicted values in original space 
Y_all_norm = zeros(num_drugs, num_data); %response values in normalized space
Loss_1 = zeros(num_drugs, num_data); %MSE
Loss_2 = zeros(num_drugs, num_data); %LPP
Loss_3 = zeros(num_drugs, num_data); %LPP train
Loss_4 = zeros(num_drugs, num_data); %MSE train
Loss_1_norm = zeros(num_drugs, num_data); %MSE in normalized space
Loss_2_norm = zeros(num_drugs, num_data); %LPP in normalized space
Loss_3_norm = zeros(num_drugs, num_data); %LPP train in normalized space
Loss_4_norm = zeros(num_drugs, num_data); %MSE train in normalized space
decisions = zeros(num_drugs, num_data); 
tic

sparse_params_array = [];
for drug = 1: num_drugs
    %do LOO cross validation 
    disp(['drug number ', num2str(drug), ' from ', num2str(num_drugs), '. acc time = ', num2str(toc) ]);
    for test_ind = 1:num_data      
        disp(['test number ', num2str(test_ind), ' from ', num2str(num_data), '. acc time = ', num2str(toc) ]);
        % divide the data into training and test
        test_index = false(num_data,1);
        test_index(test_ind) = true;
        X_train = X_all(~test_index,:)';
        Y_train = Y_all(~test_index,drug);
        X_test = X_all(test_index,:)';
        Y_test = Y_all(test_index,drug);
        %% normalize the data 
        %normalise training data
        x_mean  = mean(X_train,2);
        x_std   = std(X_train')'; 
        %some of the x_stds can be zero if training size is small. don't divide the data by std if std==0    
        x_std(x_std==0) = 1;
        X_train = bsxfun(@minus,X_train,x_mean);
        X_train = bsxfun(@rdivide, X_train, x_std);
        X_test  = bsxfun(@minus,X_test,x_mean);
        X_test  = bsxfun(@rdivide, X_test, x_std);  

        y_mean  = mean(Y_train);
        y_std   = std(Y_train); 
        Y_train = (Y_train - y_mean)./y_std;    
        Y_test_normalized = (Y_test - y_mean)./y_std; 
        Y_all_norm(drug, test_ind) = Y_test_normalized;
        
%         %Find constant features. Due to some numerical issues after the normalization, we need to consider an epsilon distance
%         non_const_features = (std(X_train')>0.00001 | std(X_train')<-0.00001);
%         %remove the all constant features from the training and test data
%         x_train = X_train(non_const_features,:);
%         x_test  = X_test(non_const_features,:);
        %remove the features that are the same for all data
        [x_train,selected_features,feature_intex_all] = unique(X_train,'rows');
        x_test = X_test(selected_features,:);
        %now feedback on the i^th feature, i.e. feedback(i), would be feedback on feature feature_intex_all(i)

%         %The next line needs to be used only once! (it is another CV on training for parameter tuning)
%         [ sparse_params ] = cross_validation_genome( x_train, Y_train, sparse_options );
%         sparse_params_array = [sparse_params_array, sparse_params];
        sparse_params.p_u = model_params.P_user;
        sparse_params.eta2 = model_params.Nu_user^2;
        
        sparse_options.si = [];   % carry prior site terms between interactions

        %calculate the posterior based on training + feedback until now
        posterior = calculate_posterior(x_train, Y_train, Feedback, model_params, MODE, sparse_params, sparse_options);
        
        %% compute different types of errors that you want        
        Y_hat = x_test'*posterior.mean;
        Y_hat_norm(drug, test_ind) = Y_hat;
        
        %Normalized MSE values
        [mse,log_pp_test,log_pp_train, mse_train] = calculate_loss(x_train,Y_train, posterior, ...
            x_test, Y_hat, Y_test_normalized, model_params);
        Loss_1_norm(drug, test_ind) = mse;
        Loss_2_norm(drug, test_ind) = log_pp_test;
        Loss_3_norm(drug, test_ind) = log_pp_train;
        Loss_4_norm(drug, test_ind) = mse_train;       
        %unnormalized MSE values
        Y_hat = Y_hat .* y_std + y_mean;
        Y_hat_all(drug, test_ind) = Y_hat;
        [mse,log_pp_test,log_pp_train, mse_train] = calculate_loss(x_train,Y_train, posterior, ...
            x_test, Y_hat, Y_test, model_params);
        Loss_1(drug, test_ind) = mse;
        Loss_2(drug, test_ind) = log_pp_test;
        Loss_3(drug, test_ind) = log_pp_train;
        Loss_4(drug, test_ind) = mse_train;
        
    end
end
%% averaging and plotting
Y_all = Y_all';
save('results_genome', 'Loss_1', 'Loss_2', 'Loss_3', 'Loss_4', 'Loss_1_norm', 'Loss_2_norm', 'Loss_3_norm', 'Loss_4_norm',...
    'drug_names', 'drug_indices', 'Y_hat_norm', 'Y_hat_all', 'Y_all', 'Y_all_norm', 'decisions', 'model_params', 'sparse_options','sparse_params', ...
     'num_features','num_trainingdata', 'MODE')
evaluate_results_genome

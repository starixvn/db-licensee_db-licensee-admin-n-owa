/*<info serverAlias="DBCUST-bodb_Licensee" executers="wsv_nap" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE [dbo].[LA_Statement_Payment_Ins]
	@PaymentNo      VARCHAR(50), 
    @ReceivedDate   SMALLDATETIME, 
    @FromCustomer   VARCHAR(30), 
    @ToCustomer     VARCHAR(30), 
    @Template       TINYINT, -- 1: Automate transfer, 0: Cross currency transfer
    @Amount         MONEY = 0, 
    @ToAmount       MONEY = 0, 
    @ActualRate     FLOAT = 1, 
    @RebatePayment  VARCHAR(1) = 'N',
    @Refno          BIGINT = NULL,
    @UserID         INT,
	@Environment    VARCHAR(10) = 'LOCAL',
    @ErrCode        INT = 0 OUTPUT,
    @ErrMsg         NVARCHAR(200) = '' OUTPUT,
    @IP             VARCHAR(45),
	@Description	NVARCHAR(200)
AS

/*
	Created: 20230908@Danny
	DB: DBCUST.bodb_Licensee
	Task: Upload payment - Record payment
   
	Revisions: 
		- 20230913@Danny: Initialize SP [#193656]

	Param's Explanation:

*/

BEGIN
	SET NOCOUNT ON
	-- Validation
	DECLARE @FromPayerID INT, @ToPayerID INT, @PaymentType TINYINT = 0, @FromCurrencyID INT , @ToCurrencyID INT, @PaymentId INT, @Remark NVARCHAR(500)
			,@FromLicenseeName VARCHAR(50), @ToLicenseeName VARCHAR(50)

	-- log
	DECLARE @startRun		DATETIME
			,@endRun		DATETIME
			,@duration		INT
			,@logSPData		NVARCHAR(MAX)
			,@logSPDataOld	NVARCHAR(MAX)
			,@logSPData_Tocust	NVARCHAR(MAX)
			,@logSPDataOld_Tocust	NVARCHAR(MAX)
			,@actionID		INT = 2101 -- Insert new payment

	-- Time start
	SET @startRun = GETDATE()

	SELECT TOP 1 @FromPayerID = op.PartyID , @FromLicenseeName = p.PartyName
	FROM OAS_PartyBaseCurrency op WITH (NOLOCK)
	INNER JOIN OAS_Party p WITH (NOLOCK) ON op.PartyID = p.PartyID
	WHERE op.LicenseeCode = @FromCustomer

	SELECT TOP 1 @ToPayerID = op.PartyID ,@ToLicenseeName = p.PartyName
	FROM OAS_PartyBaseCurrency op WITH (NOLOCK)
	INNER JOIN OAS_Party p WITH (NOLOCK) ON op.PartyID = p.PartyID
	WHERE op.LicenseeCode = @ToCustomer

	IF  @FromPayerID IS NULL
	BEGIN
		SELECT @ErrCode = 100, @ErrMsg = 'Invalid From Cust.'
		RETURN
	END

	IF  @FromPayerID IS NOT NULL AND @ToPayerID IS NOT NULL
		SELECT @PaymentType = 1 -- Transfer from main to sub

	IF  @FromPayerID IS NOT NULL AND @ToPayerID IS NULL AND @RebatePayment = 'Y' 
		SELECT @PaymentType = 2 -- Rebate payment
		

	IF @Refno IS NULL
	BEGIN
		SELECT @ErrCode = 102, @ErrMsg = 'Payment No doesn''t exist transfer collection.'
		RETURN
	END


	IF @Amount = 0
	BEGIN
		SELECT @ErrCode = 103, @ErrMsg = 'Invalid Amount.'
		RETURN
	END

	BEGIN TRY
		-- Insert 
		DECLARE @FromPaymentCurrencyID INT, @ToPaymentCurrencyID INT

		SELECT @FromPaymentCurrencyID = c.currency FROM CustDB.dbo.CustInfo c WITH(NOLOCK) WHERE c.username = @FromCustomer
		SELECT @ToPaymentCurrencyID = c.currency FROM CustDB.dbo.CustInfo c WITH(NOLOCK) WHERE c.username = @ToCustomer

		IF @PaymentType IN (0,2)
		BEGIN


			SELECT @Remark = CASE WHEN  @PaymentType IN (0,2) AND @Amount > 0 THEN  'Payment received'
								  WHEN  @PaymentType IN (0,2) AND @Amount < 0 THEN  'Payment made'
							 END
			INSERT INTO LA_Payment ([PaymentNo],[ReceivedDate],[Type],[PartyID],[CurrencyId],[Amount],[RemainingAmount],
				[TransferRefno],[StatusId],[Environment],[CreatedDate],[CreatedBy],[ModifyDate],[ModifiedBy], [Remark])
			VALUES (@PaymentNo, @ReceivedDate, @PaymentType, @FromPayerID, @FromPaymentCurrencyID, @Amount, @Amount, 
					@Refno,0 ,@Environment, GETDATE(), @UserID, GETDATE(), @UserID, @Remark )

		END

		IF @PaymentType = 1
		BEGIN

			BEGIN TRY
				-- New payment (sub-lincensee)
				INSERT INTO LA_Payment ([PaymentNo],[ReceivedDate],[Type],[PartyID],[CurrencyId],[Amount],[RemainingAmount],
					[TransferRefno],[StatusId],[Environment],[CreatedDate],[CreatedBy],[ModifyDate],[ModifiedBy], Remark)
				VALUES (@PaymentNo, @ReceivedDate, @PaymentType, @FromPayerID, @FromPaymentCurrencyID, @Amount, @Amount, 
						@Refno, 0 ,@Environment, GETDATE(), @UserID, GETDATE(), @UserID, 'Transfer from ' + @FromLicenseeName)

				INSERT INTO LA_Payment ([PaymentNo],[ReceivedDate],[Type],[PartyID],[CurrencyId],[Amount],[RemainingAmount],
					[TransferRefno],[StatusId],[Environment],[CreatedDate],[CreatedBy],[ModifyDate],[ModifiedBy], Remark)
				VALUES (@PaymentNo, @ReceivedDate, @PaymentType, @ToPayerID, @ToPaymentCurrencyID, CASE WHEN @Template = 0 THEN -@ToAmount ELSE -@Amount END, CASE WHEN  @Template = 0 THEN -@ToAmount ELSE -@Amount END, 
						@Refno, 0 ,@Environment, GETDATE(), @UserID, GETDATE(), @UserID,  'Transfer to ' + @ToLicenseeName)

			END TRY
			BEGIN CATCH
				SELECT @ErrCode = 105, @ErrMsg = 'Add new sub payment failed.'
		END

	END TRY
	BEGIN CATCH
		SELECT @ErrCode = 999, @ErrMsg = 'Record payment failed.'
		RETURN
	END CATCH

	-- Write log
	IF @Template = 0
	BEGIN
		SELECT @logSPData = (
				SELECT	 Op.PartyName	AS 'gi.p'
						 ,CAST( t.Refno AS VARCHAR(100)) AS 'gi.r'
						 ,t.PaymentNo   AS 'pi.pn'
						 ,t.ReceivedDate AS 'pi.rd'
						 ,t.FromCustomer AS 'pi.fc'
						 ,t.ToCustomer AS 'pi.tc'
						 ,FORMAT(t.FromAmount,'N','en-us') AS 'pi.fa'
						 ,FORMAT(t.ToAmount,'N','en-us') AS 'pi.ta'
						 ,t.RebatePayment AS 'pi.rp'
						 ,t.Description AS 'pi.d'
				FROM (
					SELECT @FromPayerID AS PartyID, @Refno AS Refno, @PaymentNo AS PaymentNo,  CONVERT(VARCHAR, @ReceivedDate, 101) ReceivedDate, 
						   @FromCustomer AS FromCustomer, @ToCustomer AS ToCustomer, @Amount AS FromAmount, @ToAmount AS ToAmount, @RebatePayment RebatePayment,
						   @Description AS Description
				) t
				INNER JOIN OAS_Party op WITH(NOLOCK)  ON t.PartyID = op.PartyID
				FOR JSON PATH , WITHOUT_ARRAY_WRAPPER , INCLUDE_NULL_VALUES    
			)

			IF @PaymentType = 1
				SELECT @logSPData_Tocust = (
					SELECT	 Op.PartyName	AS 'gi.p'
							 ,CAST( t.Refno AS VARCHAR(100)) AS 'gi.r'
							 ,t.PaymentNo   AS 'pi.pn'
							 ,t.ReceivedDate AS 'pi.rd'
							 ,t.FromCustomer AS 'pi.fc'
							 ,t.ToCustomer AS 'pi.tc'
							 ,FORMAT(t.FromAmount,'N','en-us') AS 'pi.fa'
							 ,FORMAT(t.ToAmount,'N','en-us') AS 'pi.ta'
							 ,t.RebatePayment AS 'pi.rp'
							 ,t.Description AS 'pi.d'
					FROM (
						SELECT @ToPayerID AS PartyID, @Refno AS Refno, @PaymentNo AS PaymentNo,  CONVERT(VARCHAR, @ReceivedDate, 101) ReceivedDate, 
							   @FromCustomer AS FromCustomer, @ToCustomer AS ToCustomer, @Amount AS FromAmount, @ToAmount AS ToAmount, @RebatePayment RebatePayment,
							   @Description AS Description
					) t
					INNER JOIN OAS_Party op WITH(NOLOCK)  ON t.PartyID = op.PartyID
					FOR JSON PATH , WITHOUT_ARRAY_WRAPPER , INCLUDE_NULL_VALUES    
				)
	END

	IF @Template = 1
	BEGIN
		SELECT @logSPData = (
				SELECT	 Op.PartyName	AS 'gi.p'
						 ,CAST( t.Refno AS VARCHAR(100)) AS 'gi.r'
						 ,t.PaymentNo   AS 'pi.pn'
						 ,t.ReceivedDate AS 'pi.rd'
						 ,t.FromCustomer AS 'pi.fc'
						 ,t.ToCustomer AS 'pi.tc'
						 ,FORMAT(t.FromAmount,'N','en-us') AS 'pi.a'
						 ,FORMAT(t.ActualRate,'G5','en-us') AS 'pi.ar'
						 ,t.RebatePayment AS 'pi.rp'
						 ,t.Description AS 'pi.d'
				FROM (
					SELECT @FromPayerID AS PartyID, @Refno AS Refno, @PaymentNo AS PaymentNo,  CONVERT(VARCHAR, @ReceivedDate, 101) ReceivedDate, 
						   @FromCustomer AS FromCustomer, @ToCustomer AS ToCustomer, @Amount AS FromAmount, @ActualRate AS ActualRate, @RebatePayment RebatePayment,
						   @Description AS Description
				) t
				INNER JOIN OAS_Party op WITH(NOLOCK)  ON t.PartyID = op.PartyID
				FOR JSON PATH , WITHOUT_ARRAY_WRAPPER , INCLUDE_NULL_VALUES    
			)

			IF @PaymentType = 1
				SELECT @logSPData_Tocust = (
					SELECT	 Op.PartyName	AS 'gi.p'
							 ,CAST( t.Refno AS VARCHAR(100)) AS 'gi.r'
							 ,t.PaymentNo   AS 'pi.pn'
							 ,t.ReceivedDate AS 'pi.rd'
							 ,t.FromCustomer AS 'pi.fc'
							 ,t.ToCustomer AS 'pi.tc'
							 ,FORMAT(t.FromAmount,'N','en-us') AS 'pi.a'
							 ,FORMAT(t.ActualRate,'G5','en-us') AS 'pi.ar'
							 ,t.RebatePayment AS 'pi.rp'
							 ,t.Description AS 'pi.d'
					FROM (
						SELECT @ToPayerID AS PartyID, @Refno AS Refno, @PaymentNo AS PaymentNo,  CONVERT(VARCHAR, @ReceivedDate, 101) ReceivedDate, 
							   @FromCustomer AS FromCustomer, @ToCustomer AS ToCustomer, @Amount AS FromAmount, @ActualRate AS ActualRate, @RebatePayment RebatePayment,
							   @Description AS Description
					) t
					INNER JOIN OAS_Party op WITH(NOLOCK)  ON t.PartyID = op.PartyID
					FOR JSON PATH , WITHOUT_ARRAY_WRAPPER , INCLUDE_NULL_VALUES    
				)
		END

	SET @endRun = GETDATE()
	SET @duration = DATEDIFF(MILLISECOND, @startRun, @endRun)


	-- Write Log
	EXEC CustDB.dbo.LA_WriteLog_UserLog_RunSP_Wrapper
		@UserId			 = @UserID
		,@IP			 = @IP
		,@SPName		 = 'LA_Statement_Payment_Ins'
		,@CustId		 = @FromPayerID
		,@Duration		 = @duration
		,@TrackingValue2 = @LogSPData
		,@TrackingValue  = @LogSPDataOld
		,@ActionID		 = @actionID

	IF @PaymentType = 1
		EXEC CustDB.dbo.LA_WriteLog_UserLog_RunSP_Wrapper
			@UserId			 = @UserID
			,@IP			 = @IP
			,@SPName		 = 'LA_Statement_Payment_Ins'
			,@CustId		 = @ToPayerID
			,@Duration		 = @duration
			,@TrackingValue2 = @logSPData_Tocust
			,@TrackingValue  = @logSPDataOld_Tocust
			,@ActionID		 = @actionID

END
GO
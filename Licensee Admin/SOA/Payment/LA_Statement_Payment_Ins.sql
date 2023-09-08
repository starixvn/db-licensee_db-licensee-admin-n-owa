/*<info serverAlias="DBCUST-bodb_Licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
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
	DECLARE @FromPayerID INT, @ToPayerID INT, @PaymentType TINYINT = 0, @FromCurrencyID INT , @ToCurrencyID INT, @PaymentId INT
	DECLARE @FromTransInfo TABLE (PayerID INT, RemainingAmount MONEY)
	DECLARE @ToTransInfo TABLE (PayerID INT, RemainingAmount MONEY)

	-- log
	DECLARE @startRun		DATETIME
			,@endRun		DATETIME
			,@duration		INT
			,@logSPData		NVARCHAR(MAX)
			,@logSPDataOld	NVARCHAR(MAX)
			,@actionID		INT = 2101 -- Insert new payment

	-- Time start
	SET @startRun = GETDATE()

	SELECT TOP 1 @FromPayerID = PartyID FROM OAS_PartyBaseCurrency op WITH (NOLOCK) WHERE op.LicenseeCode = @FromCustomer
	SELECT TOP 1 @ToPayerID = PartyID FROM OAS_PartyBaseCurrency op WITH (NOLOCK) WHERE op.LicenseeCode = @ToCustomer

	IF  @FromPayerID IS NULL
	BEGIN
		SELECT @ErrCode = 100, @ErrMsg = 'Invalid From Cust.'
		RETURN
	END

	IF  @FromPayerID IS NOT NULL AND @ToPayerID IS NOT NULL
		SELECT @PaymentType = 1 -- Transfer from main to sub

	IF  @FromPayerID IS NOT NULL AND @ToPayerID IS NULL AND @RebatePayment = 'Y' 
		SELECT @PaymentType = 2 -- Rebate payment
		
	IF @PaymentType IN (0,2) 
			AND EXISTS (SELECT TOP 1 1 FROM LA_Payment WITH(NOLOCK) WHERE PaymentNo = @PaymentNo)
	BEGIN
		SELECT @ErrCode = 101, @ErrMsg = 'Payment No exists in the system.'
		RETURN

	END

	IF @PaymentType = 1
			AND NOT EXISTS (
							SELECT TOP 1 1 FROM LA_Payment WITH(NOLOCK) 
							WHERE PaymentNo = @PaymentNo 
								AND PartyID = @ToPayerID 
								AND RemainingAmount >= CASE WHEN @Template = 1 THEN @Amount * @ActualRate
								                            WHEN @Template = 0 THEN @ToAmount END
								AND Type = 0
								)
	BEGIN
		SELECT @ErrCode = 101, @ErrMsg = 'Payment No doesn''t exist or the payment is insufficient for the transfer.'
		RETURN

	END

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
		DECLARE @PaymentCurrencyID INT

		SELECT @PaymentCurrencyID = c.currency FROM CustDB.dbo.CustInfo c WITH(NOLOCK) WHERE c.username = @FromCustomer

		IF @PaymentType IN (0,2)
		BEGIN
			INSERT INTO LA_Payment ([PaymentNo],[ReceivedDate],[Type],[PartyID],[CurrencyId],[Amount],[RemainingAmount],
				[TransferRefno],[StatusId],[Environment],[OriginalTransId],[CreatedDate],[CreatedBy],[ModifyDate],[ModifiedBy])
			VALUES (@PaymentNo, @ReceivedDate, @PaymentType, @FromPayerID, @PaymentCurrencyID, @Amount, @Amount, 
					@Refno,0 ,@Environment, NULL, GETDATE(), @UserID, GETDATE(), @UserID  )

			SET @PaymentId = SCOPE_IDENTITY()
		END

		IF @PaymentType = 1
		BEGIN
			DECLARE @OriginalTransId INT -- Main payment
			SELECT @OriginalTransId = PaymentId FROM LA_Payment WITH(NOLOCK) WHERE PaymentNo = @PaymentNo AND PartyID = @ToPayerID AND Type = 0

			-- Update old payemnt (main-licensee)
			BEGIN TRY
				UPDATE LA_Payment WITH(ROWLOCK, UPDLOCK)
				SET		RemainingAmount = ROUND(RemainingAmount - CASE WHEN @Template = 1 THEN @Amount * @ActualRate
																 WHEN @Template = 0 THEN @ToAmount END,2)
				OUTPUT INSERTED.PaymentId ,INSERTED.RemainingAmount INTO @FromTransInfo
				WHERE PaymentNo = @PaymentNo AND PartyID = @ToPayerID AND Type = 0
			END TRY
			BEGIN CATCH
				SELECT @ErrCode = 104, @ErrMsg = 'Update remaining amount of main payment failed'
				RETURN
			END CATCH

			BEGIN TRY
				-- New payment (sub-lincensee)
				INSERT INTO LA_Payment ([PaymentNo],[ReceivedDate],[Type],[PartyID],[CurrencyId],[Amount],[RemainingAmount],
					[TransferRefno],[StatusId],[Environment],[OriginalTransId],[CreatedDate],[CreatedBy],[ModifyDate],[ModifiedBy])
				OUTPUT INSERTED.PaymentId ,INSERTED.RemainingAmount INTO @ToTransInfo
				VALUES (@PaymentNo, @ReceivedDate, @PaymentType, @FromPayerID, @PaymentCurrencyID, @Amount, @Amount, 
						@Refno, 0 ,@Environment, @OriginalTransId, GETDATE(), @UserID, GETDATE(), @UserID)

				SET @PaymentId = SCOPE_IDENTITY()

			END TRY
			BEGIN CATCH
				SELECT @ErrCode = 105, @ErrMsg = 'Add new sub payment failed.'

				-- Rollback remaining amount Main-payment
				UPDATE LA_Payment WITH(ROWLOCK, UPDLOCK)
				SET		RemainingAmount = ROUND(RemainingAmount + CASE WHEN @Template = 1 THEN @Amount * @ActualRate
																 WHEN @Template = 0 THEN @ToAmount END,2)
				WHERE PaymentNo = @PaymentNo AND PartyID = @ToPayerID AND Type = 0

				RETURN
			END CATCH

			-- Allocate payment to payment: Type = 3
			BEGIN TRY

				DECLARE @FromRemainingAmount MONEY, @ToRemainingAmount MONEY
				SELECT @FromRemainingAmount = RemainingAmount FROM @FromTransInfo
				SELECT @ToRemainingAmount = RemainingAmount FROM @FromTransInfo

				INSERT INTO LA_Allocation (FromTransId,ToTransId,Type,AppliedAmount,FromRemainingAmount,ToRemainingAmount,StatusId,
											CreatedDate,CreatedBy,UpdatedDate,UpdatedBy)
				SELECT  @OriginalTransId, @PaymentId, 3, CASE WHEN @Template = 1 THEN ROUND(@Amount * @ActualRate,2)
														      WHEN @Template = 0 THEN @ToAmount END, 
						@FromRemainingAmount, @ToRemainingAmount, 0,  GETDATE(), @UserID, GETDATE(), @UserID 
				
			END TRY

			BEGIN CATCH
				-- Remove sub payment 
				DELETE FROM LA_Payment WITH(ROWLOCK, UPDLOCK) WHERE PaymentId = @PaymentId

				-- Rollback remaining amount Main-payment
				UPDATE LA_Payment WITH(ROWLOCK, UPDLOCK)
				SET		RemainingAmount = ROUND(RemainingAmount + CASE WHEN @Template = 1 THEN @Amount * @ActualRate
																 WHEN @Template = 0 THEN @ToAmount END,2)
				WHERE PaymentNo = @PaymentNo AND PartyID = @ToPayerID AND Type = 0


				SELECT @ErrCode = 106, @ErrMsg = 'Add new sub payment failed.'

				RETURN
				
			END CATCH

		END

	END TRY
	BEGIN CATCH
		SELECT @ErrCode = 999, @ErrMsg = 'Record payment failed.'
		RETURN
	END CATCH

	-- Write log
	IF @Template = 0
		SELECT @logSPData = (
				SELECT	 Op.PartyName	AS 'gi.p'
						 ,t.Refno		AS 'gi.r'
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


	IF @Template = 1
		SELECT @logSPData = (
				SELECT	 Op.PartyName	AS 'gi.p'
						 ,t.Refno		AS 'gi.r'
						 ,t.PaymentNo   AS 'pi.pn'
						 ,t.ReceivedDate AS 'pi.rd'
						 ,t.FromCustomer AS 'pi.fc'
						 ,t.ToCustomer AS 'pi.tc'
						 ,FORMAT(t.FromAmount,'N','en-us') AS 'pi.fa'
						 ,FORMAT(t.ActualRate,'N','en-us') AS 'pi.ar'
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

	
END
GO
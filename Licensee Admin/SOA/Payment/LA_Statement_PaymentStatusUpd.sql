/*<info serverAlias="DBCUST-bodb_licensee" executers="wsv_nap" isFunction="0" isNested="0"></info>*/
USE [bodb_licensee]
GO

ALTER PROCEDURE [dbo].[LA_Statement_PaymentStatusUpd]
	@TransferRefno	BIGINT,
	@StatusId		INT,
	@VoidTime		SMALLDATETIME,
	@UserId			INT,
	@LoginIp		VARCHAR(20),
	@ErrCode		INT = 0 OUTPUT,
	@ErrMsg			VARCHAR(1000) = '' OUTPUT
AS
/*	Header:
	Created: 20240715@Danny
	Task :	Void payment
	DB:		DBCUST.bodb_Licensee

	Revisions:
		- 20240715@Danny: Create new SP for void payment [RedmineID: #206990]
*/
BEGIN
	SET NOCOUNT ON
	-- log
	DECLARE @startRun		DATETIME
			,@endRun		DATETIME
			,@duration		INT
			,@logSPData		NVARCHAR(MAX)
			,@logSPDataOld	NVARCHAR(MAX)
			,@actionID		INT = 2102 -- Void payment

	-- Time start
	SET @startRun = GETDATE()


	DECLARE @VoidedPaymentList TABLE (ID INT Identity(1,1), PaymentID INT, StatusID SMALLINT, Amount MONEY, RemainingAmount MONEY, PartyID INT)

	INSERT INTO @VoidedPaymentList (PaymentID, StatusID, Amount, RemainingAmount, PartyID)
	SELECT PaymentID, StatusID, Amount, RemainingAmount, PartyID FROM LA_Payment WITH(NOLOCK) WHERE TransferRefno = @TransferRefno


	IF EXISTS (SELECT 1 FROM @VoidedPaymentList WHERE StatusId = -1) --void
	BEGIN
		SELECT @ErrCode = 1000, @ErrMsg = 'This payment has already been voided!'
		RETURN
	END

	IF EXISTS (SELECT 1 FROM @VoidedPaymentList WHERE Amount <> RemainingAmount) --Allocated
	BEGIN
		SELECT @ErrCode = 1001, @ErrMsg = 'The payment could not be voided since it is fully/partially allocated. Please contact Starix for support.'
		RETURN
	END

	BEGIN TRY
		UPDATE dbo.LA_Payment WITH(ROWLOCK, UPDLOCK)
		SET StatusId = @StatusId, ModifiedBy = @UserId, ModifyDate=@VoidTime
		WHERE PaymentId IN (SELECT z.PaymentId FROM  @VoidedPaymentList z)
	END TRY
	BEGIN CATCH
		SELECT @ErrCode = 1002, @ErrMsg = 'The server encountered a temporary error and could not complete your request. Please try again!'
		RETURN
	END CATCH

	SET @endRun = GETDATE()
	SET @duration = DATEDIFF(MILLISECOND, @startRun, @endRun)


	-- Write log
	DECLARE @PartyID  INT, @PaymentID INT, @i INT = 1

	WHILE EXISTS (SELECT TOP 1 1 FROM @VoidedPaymentList WHERE ID = @i)
	BEGIN
		SElECT @PaymentID = PaymentID, @PartyID = PartyID  FROM @VoidedPaymentList WHERE ID = @i

		SELECT @logSPData = 
		(
			SELECT	Op.PartyName	AS 'gi.p',
					CAST(lp.TransferRefno AS VARCHAR(100)) AS 'gi.r',
					lp.PaymentNo	AS 'pi.pn',
					bi.BillerNameAbbreviation  AS 'pi.b',
					CASE WHEN lp.Type = 0 THEN 'Payment'
						 WHEN lp.Type = 1 THEN 'Transfer between 2 licensees'
						 WHEN lp.Type = 2 THEN 'Rebate Payment' END 'pi.pt',
					FORMAT(lp.Amount,'N','en-us') AS 'pi.a',
					FORMAT(lp.RemainingAmount,'N','en-us') AS  'pi.ra',
					FORMAT (lp.ReceivedDate,'MMM dd, yyyy') AS 'pi.rd',
					FORMAT (lp.CreatedDate,'MMM dd, yyyy') AS 'pi.ud',
					lu.Username AS 'pi.mb', -- Modified By
					FORMAT (lp.ModifyDate ,'MMM dd, yyyy hh:mm:ss tt') AS 'pi.md'
	
			FROM	LA_Payment lp WITH(NOLOCK)
			INNER JOIN OAS_Party op WITH(NOLOCK) ON lp.PartyID = op.PartyID
			INNER JOIN LA_BillerInfo bi WITH(NOLOCK) ON bi.PartyId = lp.BillerId
			LEFT JOIN LA_User lu WITH(NOLOCK) ON lu.UserID = lp.ModifiedBy 
			WHERE lp.PaymentId = @PaymentID
			FOR JSON PATH , WITHOUT_ARRAY_WRAPPER , INCLUDE_NULL_VALUES   
		)

		-- Write Log
		EXEC CustDB.dbo.LA_WriteLog_UserLog_RunSP_Wrapper
			@UserId			 = @UserID
			,@IP			 = @LoginIp
			,@SPName		 = 'LA_Statement_PaymentStatusUpd'
			,@CustId		 = @PartyID
			,@Duration		 = @duration
			,@TrackingValue2 = @LogSPData
			,@TrackingValue  = @LogSPDataOld
			,@ActionID		 = @actionID

		SELECT @i = @i + 1

	END


	


	SELECT @ErrCode = 0, @ErrMsg = ''
END
GO
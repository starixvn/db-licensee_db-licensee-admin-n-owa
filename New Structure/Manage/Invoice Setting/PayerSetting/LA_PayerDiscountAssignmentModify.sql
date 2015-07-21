USE [bodb_licensee]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[LA_PayerDiscountAssignmentModify]
	@PayerList				VARCHAR(500)
	, @DiscountGroupId		INT				
	, @UserID				INT
	, @Mode					VARCHAR(10)		= ''
	, @LoginIP				VARCHAR (50)	= ''
	, @ErrCode				INT				= 0		OUTPUT
	, @ErrMsg				NVARCHAR(1000)	= ''	OUTPUT	
AS
/*  
	 Created: 20150422@Florent
	 Task : add/modify Payer Discount Assignment setting
	 DB: DB052.bodb_Licensee  
   
	 Revisions:     		  
	 Params:		
	 Example:
	
*/
BEGIN	
SET NOCOUNT ON
	-- For writing log
	DECLARE @startRun DATETIME
		, @endRun DATETIME
		, @duration INT
		, @logSPData VARCHAR(5000)
		, @logSPDataOld VARCHAR(5000)
		, @xml XML
		, @todate DATETIME
		, @DiscountTypeId	INT
	-- Time start
	SET @startRun = GETDATE()
	SET @todate = CONVERT(DATE, GETDATE())

	IF ISNULL(@DiscountGroupId, 0) = 0
		RETURN
	IF NOT EXISTS( SELECT 1 FROM dbo.LA_DiscountGroupHeader h WITH (NOLOCK) WHERE h.DiscountGroupId = @DiscountGroupId)
		RETURN

	SELECT @DiscountTypeId = h.DiscountGroupType FROM dbo.LA_DiscountGroupHeader h WITH (NOLOCK) WHERE h.DiscountGroupId = @DiscountGroupId	
	DECLARE @PayerDiscountList AS TABLE (DiscountGroupId INT, PartyID INT)		
	INSERT INTO @PayerDiscountList(DiscountGroupId, PartyID)
	SELECT @DiscountGroupId, val 
	FROM bodb02.dbo.strSplit(@PayerList, ',')
	
	-- check still valid payer discount group
	IF EXISTS( SELECT 1 FROM dbo.LA_DiscountGroupHeader h WITH (NOLOCK) 
						INNER JOIN dbo.LA_DiscountGroupAssignment a WITH (NOLOCK) ON  a.DiscountGroupId = h.DiscountGroupId
				WHERE @todate BETWEEN h.FromDate AND h.ToDate
					AND a.PartyID IN (SELECT PartyID FROM @PayerDiscountList)
					AND h.DiscountGroupType = @DiscountTypeId
					AND h.DiscountGroupId <> @DiscountGroupId)
	BEGIN
		SELECT 	@ErrMsg = 'Update failed. Please try again.', @ErrCode = 203	
		RETURN
	END
	-- check valid discount
	IF NOT EXISTS(SELECT 1 FROM dbo.LA_DiscountGroupHeader h WITH (NOLOCK)
				WHERE @todate BETWEEN h.FromDate AND h.ToDate
					AND h.DiscountGroupId = ISNULL(@DiscountGroupId, 0)
					AND h.DiscountGroupType = @DiscountTypeId)
	BEGIN
		SELECT 	@ErrMsg = 'Update failed. Please try again.', @ErrCode = 203	
				RETURN
	END
		
	--validate 
	EXEC dbo.LA_Discount_ValidatePayerAssignment
		@DiscountGroupId	= @DiscountGroupId
		, @PayerIdList	= @PayerList
		, @Mode			= @Mode
		, @ErrCode		= @ErrCode	OUTPUT
		, @ErrMsg		= @ErrMsg	OUTPUT
	IF @ErrCode <> 0
		RETURN
	-- check save exists group
	IF EXISTS( SELECT 1 
			FROM dbo.LA_DiscountGroupAssignment a WITH (NOLOCK) 
				INNER JOIN @PayerDiscountList p ON a.PartyID = p.PartyID
			WHERE a.DiscountGroupId = @DiscountGroupId)
		RETURN

	-- Case Add / modify
	BEGIN	
		;MERGE dbo.LA_DiscountGroupAssignment WITH( ROWLOCK, UPDLOCK) AS t
		USING @PayerDiscountList AS s
		ON (t.DiscountGroupId = s.DiscountGroupId AND t.PartyId = s.PartyID)
		WHEN NOT MATCHED BY TARGET
			THEN INSERT (DiscountGroupId, PartyID)
			 	 VALUES (s.DiscountGroupId, s.PartyID);

		IF @@ERROR <> 0
		BEGIN
			SELECT 	@ErrMsg = 'Update failed. Please try again.', @ErrCode = 203	
			RETURN
		END
		
		-- Write log
		SET @xml = (
			SELECT DiscountGroupId	AS '@dg'				
				, PartyId			AS '@p'
			FROM @PayerDiscountList
			FOR XML PATH('z'), ROOT('r')			
			)		

		SET @logSpData = REPLACE(CONVERT(VARCHAR(MAX), @xml), '" />', '"/"')
		SET @endRun = GETDATE()
		SET @duration = DATEDIFF(MILLISECOND, @startRun, @endRun) 
	END
	--Write Log		
	DECLARE @ActionID INT = 0
	SELECT @ActionID = ActionId
	FROM bodb_CustomerLog.dbo.LogAction_Lic WITH (NOLOCK)
	WHERE SPName = 'LA_PayerDiscountAssignmentModify'
	
	BEGIN TRY
		EXEC bodb_CustomerLog.dbo.NAP_SpecialCustSetting_WriteLog 
			@UserId = @UserID
			, @IP = @LoginIP
			, @LicenseeID = 0
			, @CurrencyID = 0
			, @SPName = 'LA_PayerDiscountAssignmentModify'
			, @CustId = 0
			, @ActionId = @ActionID
			, @Duration = @duration
			, @Data = @logSPData
			, @OldData = @logSPDataOld
	END TRY
	BEGIN CATCH
		EXEC bodb_CustomerLog.dbo.WriteLog_UserLog_RunSP 
			@UserID = @UserID
			, @CustID = 0
			, @ActionID = @ActionID
			, @TrackingValue = @LogSPData
			, @TrackingValue2 = @logSPDataOld
			, @duration = @duration
	END CATCH
END

GO
GRANT VIEW DEFINITION ON [dbo].[LA_PayerDiscountAssignmentModify] TO [vnteam] 
GRANT EXECUTE ON [dbo].[LA_PayerDiscountAssignmentModify] TO bodbAdminNet
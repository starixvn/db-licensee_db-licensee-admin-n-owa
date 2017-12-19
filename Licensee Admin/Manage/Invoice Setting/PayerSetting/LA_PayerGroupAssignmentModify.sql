USE [bodb_licensee]
GO

ALTER PROCEDURE [dbo].[LA_PayerGroupAssignmentModify]
	@PayerList				VARCHAR(4000)
	, @PayerGroupId			INT
	, @UserID				INT
	, @Mode					VARCHAR(10)		= ''
	, @LoginIP				VARCHAR (50)	= ''
	, @ErrCode				INT				= 0		OUTPUT
	, @ErrMsg				NVARCHAR(1000)	= ''	OUTPUT
AS
/*  
	 Created: 20150422@Florent
	 Task : add/modify Payer Group Assignment setting
	 DB: DB052.bodb_Licensee

	 Revisions:
	 	- 20171219@Bruce: increase length for variables [#88197]
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
	-- Time start
	SET @startRun = GETDATE()
	IF ISNULL(@PayerGroupId, 0) = 0
		RETURN
	DECLARE @PayerGroupList AS TABLE (PayerGroupId INT, PartyID INT)

	INSERT INTO @PayerGroupList(PayerGroupId, PartyID)
	SELECT @PayerGroupId, val 
	FROM bodb02.dbo.strSplit(@PayerList, ',')
	--validate 
	EXEC dbo.LA_PayerGroupValidatePayerAssignment
		@PayerGroupId	= @PayerGroupId
		, @PayerIdList	= @PayerList
		, @Mode			= @Mode
		, @ErrCode		= @ErrCode	OUTPUT
		, @ErrMsg		= @ErrMsg	OUTPUT
	IF @ErrCode <> 0
		RETURN
	
	-- Case Add / modify
	BEGIN	
		
		;MERGE dbo.LA_PartyGroupAssignment WITH( ROWLOCK, UPDLOCK) AS t
		USING @PayerGroupList AS s
		ON (t.PartyGroupId = s.PayerGroupId AND t.PartyId = s.PartyID)
		WHEN NOT MATCHED BY TARGET
			THEN INSERT (PartyGroupId, PartyID)
			 	 VALUES (s.PayerGroupId, s.PartyID);

		IF @@ERROR <> 0
		BEGIN
			SELECT 	@ErrMsg = 'Update failed. Please try again.', @ErrCode = 203	
			RETURN
		END
		
		-- Write log
		SET @xml = (
			SELECT PayerGroupId		AS '@pid'				
				, PartyId			AS '@p'
			FROM @PayerGroupList
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
	WHERE SPName = 'LA_PayerGroupAssignmentModify'
	
	BEGIN TRY
		EXEC bodb_CustomerLog.dbo.NAP_SpecialCustSetting_WriteLog 
			@UserId = @UserID
			, @IP = @LoginIP
			, @LicenseeID = 0
			, @CurrencyID = 0
			, @SPName = 'LA_PayerGroupAssignmentModify'
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
GRANT VIEW DEFINITION ON [dbo].[LA_PayerGroupAssignmentModify] TO [vnteam] 
GRANT EXECUTE ON [dbo].[LA_PayerGroupAssignmentModify] TO bodbAdminNet
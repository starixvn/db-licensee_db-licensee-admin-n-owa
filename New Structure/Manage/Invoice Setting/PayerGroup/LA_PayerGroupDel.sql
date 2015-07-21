USE [bodb_licensee]
GO
/****** Object:  StoredProcedure [dbo].[LA_PayerGroupDel]    Script Date: 23/04/2015 09:50:48 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[LA_PayerGroupDel]
	@PayerGroupId			INT	= 0		
	, @UserID				INT
	, @LoginIP				VARCHAR (50)	= ''
	, @ErrCode				INT				= 0		OUTPUT
	, @ErrMsg				NVARCHAR(1000)	= ''	OUTPUT	
AS
/*  
	 Created: 20150422@Florent
	 Task : Delete payer Group setting
	 DB: DB052.bodb_Licensee  
   
	 Revisions:     		  
	 Params:		
	 Example:
	
*/
BEGIN	
SET NOCOUNT ON
	
	-- For writing log
	DECLARE 
		@startRun		DATETIME,
		@endRun			DATETIME,
		@duration		INT,
		@logSPData		VARCHAR(5000),
		@logSPDataOld	VARCHAR(5000),
		@xml			XML

	-- Time start
	SET @startRun = GETDATE()
	DECLARE @CanDel BIT = 1
	-- check case edit
	IF NOT EXISTS (SELECT 1 FROM dbo.LA_PartyGroup WITH (NOLOCK) WHERE PartyGroupId = @PayerGroupId)
	BEGIN
		RETURN
	END
	
	-- TODO: check exists issue invoice
	--IF EXISTS (SELECT 1 
	--			FROM dbo.LA_PartyGroupAssignment a WITH (NOLOCK) 
	--			WHERE PartyGroupId = @PayerGroupId
	--				--AND EXISTS (SELECT 1 FROM dbo.la_invHeader h WHERE a.PartyId = h.PartyID)
	--			)
	--BEGIN
	--	RETURN
	--END
	
	IF NOT EXISTS (SELECT 1 
					FROM dbo.LA_PartyGroup pg WITH (NOLOCK) 
						INNER JOIN dbo.LA_PartyGroupAssignment pga WITH (NOLOCK) ON pg.PartyGroupId = pga.PartyGroupId 
					WHERE pg.PartyGroupId = @PayerGroupId
					)
	BEGIN 
		-- Write log
		SET @xml = (
			SELECT PartyGroupId		AS '@pid'
				, PartyGroupName	AS '@pn'				
			FROM dbo.LA_PartyGroup WITH (NOLOCK) 
			FOR XML PATH('z'), ROOT('r')			
			)
		SET @logSPDataOld = REPLACE(CONVERT(VARCHAR(MAX), @xml), '" />', '"/"')	

		DELETE LA_PartyGroup WITH (ROWLOCK, UPDLOCK)
		WHERE PartyGroupId = @PayerGroupId

		IF @@ERROR <> 0 
		BEGIN
			SELECT @ErrCode = 211
					, @ErrMsg = 'Delete failed. Please try again.'
			RETURN
		END			

		SET @endRun = GETDATE()
		SET @duration = DATEDIFF(MILLISECOND, @startRun, @endRun) 
		
		--Write Log		
		DECLARE @ActionID INT = 0
		SELECT @ActionID = ActionId
		FROM bodb_CustomerLog.dbo.LogAction_Lic WITH (NOLOCK)
		WHERE SPName = 'LA_PayerGroupDel'
	
		BEGIN TRY
			EXEC bodb_CustomerLog.dbo.NAP_SpecialCustSetting_WriteLog 
				@UserId = @UserID
				, @IP = @LoginIP
				, @LicenseeID = 0
				, @CurrencyID = 0
				, @SPName = 'LA_PayerGroupDel'
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
	ELSE
	BEGIN
		SELECT @ErrCode = 210
				, @ErrMsg = 'Cannot delete the group, it is being applied!'
		RETURN
	END

END
GO
GRANT VIEW DEFINITION ON [dbo].[LA_PayerGroupDel] TO [vnteam] 
GRANT EXECUTE ON [dbo].[LA_PayerGroupDel] TO bodbAdminNet 

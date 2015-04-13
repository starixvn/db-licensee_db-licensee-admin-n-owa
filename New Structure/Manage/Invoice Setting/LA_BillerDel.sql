USE [bodb_licensee]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[LA_BillerDel] 
	@BillerID	INT	
	, @UserID							INT
	, @LoginIP							VARCHAR (50)	= ''
	, @ErrCode	INT				= 0		OUTPUT
	, @ErrMsg	NVARCHAR(1000)	= ''	OUTPUT
AS
/*  
	 Created: 20150408@Florent
	 Task : Delete Biller Information
	 DB: DB052.bodb_Licensee  
   
	 Revisions:     
*/
SET NOCOUNT ON

BEGIN
	--check exist
	IF ISNULL(@BillerID, '') = ''
		RETURN
	-- only can delete which Biller dont issue any invoice on system
	DECLARE @CanDel BIT = 1
	SELECT @CanDel = 0 FROM dbo.OAS_Party p WITH (NOLOCK)
			INNER JOIN dbo.LA_BillerInfo b WITH (NOLOCK) ON p.PartyID = b.PartyID			
			INNER JOIN dbo.LA_InvoiceSetting i WITH (NOLOCK) ON i.FromPartyId = p.PartyID
			-- check exists biller in table Incoive
	WHERE p.PartyType = 4 -- biller
			AND p.PartyID = @BillerId

	IF (@CanDel = 1)
		BEGIN
			DECLARE 
				@startRun		DATETIME,
				@endRun			DATETIME,
				@duration		INT,
				@logSPData		VARCHAR(5000),
				@logSPDataOld	VARCHAR(5000),
				@xml			XML

			-- Time start
			SET @startRun = GETDATE()
	
			-- Write log
			SET @xml = (
				SELECT	PartyId							AS '@b'
						, BillerName					AS '@bn'
						, BillerFullName				AS '@bfn'
						, StatusId						AS '@s'
						, CompanyName					AS '@c'
						, Address1						AS '@a1'
						, Address2						AS '@a2'
						, LogoPath						AS '@lg'
						, [Description]					AS '@d'
						, AccountNumber					AS '@a'
						, BankName						AS '@bna'
						, BankAddess					AS '@ba'
						, IBAN							AS '@i'
						, BeneficiaryName				AS '@bd'
						, SwiftCode						AS '@sc'
						, CorrespondentBank				AS '@cb'
						, CorrespondentAccountNumber	AS '@ca'
						, CorrespondentAddress			AS '@cad'
						, CorrespondentSwiftCode		AS '@cs'
				FROM dbo.LA_BillerInfo WITH (NOLOCK)
				WHERE PartyId = @BillerID
				FOR XML PATH('z'), ROOT('r')
				)

			SET @logSPDataOld = REPLACE(CONVERT(VARCHAR(MAX), @xml), '" />', '"/"')	

			DELETE dbo.OAS_Party WITH (ROWLOCK, UPDLOCK)
			WHERE PartyType = 4 AND PartyID = @BillerId

			DELETE dbo.LA_BillerInfo WITH (ROWLOCK, UPDLOCK)
			WHERE PartyId = @BillerId
					
			SET @endRun = GETDATE()
			SET @duration = DATEDIFF(MILLISECOND, @startRun, @endRun) 
			
			--Write log	
			DECLARE @ActionID INT = 0
			SELECT @ActionID = ActionId
			FROM bodb_CustomerLog.dbo.LogAction_Lic WITH (NOLOCK)
			WHERE SPName = 'LA_BillerDel'

			EXEC bodb_CustomerLog.dbo.NAP_SpecialCustSetting_WriteLog 
				@UserId = @UserID
				, @IP = @LoginIP
				, @LicenseeID = 0
				, @CurrencyID = 0
				, @SPName = 'LA_BillerDel'
				, @CustId = 0
				, @ActionId = @ActionID
				, @Duration = @duration
				, @Data = @logSPData
				, @OldData = @logSPDataOld
			BEGIN
			SELECT @ErrCode = 101
				,@ErrMsg = 'The Biller is deleted successfully'
			RETURN
		END
		END
	ELSE	
		BEGIN
			SELECT @ErrCode = 101
			,@ErrMsg = 'The Biller cannot be deleted because it''s already responsible for billing!'
			RETURN
		END		
END

GO
GRANT VIEW DEFINITION ON [dbo].[LA_BillerDel] TO [vnteam] 
GRANT EXECUTE ON [dbo].[LA_BillerDel] TO bodbAdminNet 
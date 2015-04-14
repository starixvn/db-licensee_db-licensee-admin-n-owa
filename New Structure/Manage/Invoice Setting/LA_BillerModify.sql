USE [bodb_licensee]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[LA_BillerModify] 
	@BillerID							INT				
	, @BillerName						VARCHAR (50)	
	, @BillerFullName					VARCHAR (125)	= ''
	, @StatusId							TINYINT			
	, @CompanyName						VARCHAR (50)	= ''
	, @Address1							VARCHAR (255)	= ''
	, @Address2							VARCHAR (255)	= ''
	, @LogoPath							VARCHAR (255)	= ''
	, @Description						VARCHAR (255)	= ''
	, @AccountNumber					VARCHAR (50)	= ''
	, @BankName							VARCHAR (125)	= ''
	, @BankAddess						VARCHAR (255)	= ''
	, @IBAN								VARCHAR (50)	= ''
	, @BeneficiaryName					VARCHAR (125)	= ''
	, @SwiftCode						VARCHAR (50)	= ''
	, @CorrespondentBank				VARCHAR (50)	= ''
	, @CorrespondentAccountNumber		VARCHAR (50)	= ''
	, @CorrespondentAddress				VARCHAR (255)	= ''
	, @CorrespondentSwiftCode			VARCHAR (50)	= ''
	, @UserID							INT
	, @LoginIP							VARCHAR (50)	= ''
	, @ErrCode							INT				= 0		OUTPUT
	, @ErrMsg							NVARCHAR(1000)	= ''	OUTPUT
AS
/*  
	 Created: 20150408@Florent
	 Task : Create new Biller
	 DB: DB052.bodb_Licensee  
   
	 Revisions:     
*/
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
BEGIN
	DECLARE @ConstantName VARCHAR(20) = 'Invoice System'
	--check exist
	IF ISNULL(@BillerName, '') = ''
		RETURN

	IF NOT EXISTS (SELECT 1 FROM dbo.OAS_Party p WITH (NOLOCK) WHERE p.PartyID = @BillerID AND p.PartyType = 4)
	--Insert New Biller
	BEGIN
		IF NOT EXISTS (SELECT 1 FROM dbo.OAS_Party p WITH (NOLOCK) 
						INNER JOIN dbo.LA_BillerInfo b WITH (NOLOCK) ON p.PartyId = b.PartyID 
					 WHERE b.BillerName = @BillerName AND p.PartyType = 4)
		BEGIN
			INSERT INTO dbo.OAS_Party (PartyName, Description, PartyType, OldRefID)
			SELECT @ConstantName, @ConstantName, 4, NULL

			INSERT INTO dbo.LA_BillerInfo(PartyId, BillerName, BillerFullName, StatusId, CompanyName, Address1, Address2, LogoPath, [Description], AccountNumber, BankName, BankAddess
			, IBAN, BeneficiaryName, SwiftCode, CorrespondentBank, CorrespondentAccountNumber, CorrespondentAddress, CorrespondentSwiftCode)
			SELECT
					SCOPE_IDENTITY()
					, @BillerName
					, @BillerFullName
					, @StatusId
					, @CompanyName
					, @Address1
					, @Address2
					, @LogoPath
					, @Description
					, @AccountNumber
					, @BankName
					, @BankAddess
					, @IBAN
					, @BeneficiaryName
					, @SwiftCode
					, @CorrespondentBank
					, @CorrespondentAccountNumber
					, @CorrespondentAddress
					, @CorrespondentSwiftCode


			-- Write log
			SET @xml = (
				SELECT	SCOPE_IDENTITY()				AS '@b'
						, @BillerName					AS '@bn'
						, @BillerFullName				AS '@bfn'
						, @StatusId						AS '@s'
						, @CompanyName					AS '@c'
						, @Address1						AS '@a1'
						, @Address2						AS '@a2'
						, @LogoPath						AS '@lg'
						, @Description					AS '@d'
						, @AccountNumber				AS '@a'
						, @BankName						AS '@bna'
						, @BankAddess					AS '@ba'
						, @IBAN							AS '@i'
						, @BeneficiaryName				AS '@bd'
						, @SwiftCode					AS '@sc'
						, @CorrespondentBank			AS '@cb'
						, @CorrespondentAccountNumber	AS '@ca'
						, @CorrespondentAddress			AS '@cad'
						, @CorrespondentSwiftCode		AS '@cs'
				FOR XML PATH('z'), ROOT('r')			
				)

			SET @logSpData = REPLACE(CONVERT(VARCHAR(MAX), @xml), '" />', '"/"')	

			SET @endRun = GETDATE()
			SET @duration = DATEDIFF(MILLISECOND, @startRun, @endRun) 	
		END
		ELSE
		BEGIN
			SELECT @ErrCode = 101
			,@ErrMsg = 'Cannot save the Biller because it existed in the system, please try again!'
			RETURN
		END
	END
	ELSE
	--Edit Biller
	BEGIN		
		IF EXISTS (SELECT 1 FROM dbo.OAS_Party p WITH (NOLOCK) 
						INNER JOIN dbo.LA_BillerInfo b WITH (NOLOCK) ON p.PartyId = b.PartyID 
					 WHERE p.PartyID = @BillerID AND p.PartyType = 4)
		BEGIN
			--write log old
			-- Write log
			SET @xml = (
				SELECT	BillerName						AS '@bn'
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

			UPDATE dbo.LA_BillerInfo WITH (ROWLOCK, UPDLOCK)
			SET BillerName					 = @BillerName
				, BillerFullName			 = @BillerFullName
				, StatusId					 = @StatusId
				, CompanyName				 = @CompanyName
				, Address1					 = @Address1
				, Address2					 = @Address2
				, LogoPath					 = @LogoPath
				, Description				 = @Description
				, AccountNumber				 = @AccountNumber
				, BankName					 = @BankName
				, BankAddess				 = @BankAddess
				, IBAN						 = @IBAN
				, BeneficiaryName			 = @BeneficiaryName
				, SwiftCode					 = @SwiftCode
				, CorrespondentBank			 = @CorrespondentBank
				, CorrespondentAccountNumber = @CorrespondentAccountNumber
				, CorrespondentAddress		 = @CorrespondentAddress
				, CorrespondentSwiftCode	 = @CorrespondentSwiftCode
			WHERE PartyId = @BillerID	

			SET @xml = (
			SELECT	@BillerName							AS '@bn'
						, @BillerFullName				AS '@bfn'
						, @StatusId						AS '@s'
						, @CompanyName					AS '@c'
						, @Address1						AS '@a1'
						, @Address2						AS '@a2'
						, @LogoPath						AS '@lg'
						, @Description					AS '@d'
						, @AccountNumber				AS '@a'
						, @BankName						AS '@bna'
						, @BankAddess					AS '@ba'
						, @IBAN							AS '@i'
						, @BeneficiaryName				AS '@bd'
						, @SwiftCode					AS '@sc'
						, @CorrespondentBank			AS '@cb'
						, @CorrespondentAccountNumber	AS '@ca'
						, @CorrespondentAddress			AS '@cad'
						, @CorrespondentSwiftCode		AS '@cs'
				FOR XML PATH('z'), ROOT('r')			
				)

			SET @logSpData = REPLACE(CONVERT(VARCHAR(MAX), @xml), '" />', '"/"')	

			SET @endRun = GETDATE()
			SET @duration = DATEDIFF(MILLISECOND, @startRun, @endRun) 	

		END		
		ELSE
		BEGIN
			SELECT @ErrCode = 101
			,@ErrMsg = 'Cannot save the Biller because it existed in the system, please try again!'
			RETURN
		END
	END
	
	--Write Log	
	DECLARE @ActionID INT = 0
	SELECT @ActionID = ActionId
	FROM bodb_CustomerLog.dbo.LogAction_Lic WITH (NOLOCK)
	WHERE SPName = 'LA_BillerModify'

	EXEC bodb_CustomerLog.dbo.NAP_SpecialCustSetting_WriteLog 
	@UserId = @UserID
	, @IP = @LoginIP
	, @LicenseeID = 0
	, @CurrencyID = 0
	, @SPName = 'LA_BillerModify'
	, @CustId = 0
	, @ActionId = ActionID
	, @Duration = @duration
	, @Data = @logSPData
	, @OldData = @logSPDataOld
END
GO
GRANT VIEW DEFINITION ON [dbo].[LA_BillerModify] TO [vnteam] 
GRANT EXECUTE ON [dbo].[LA_BillerModify] TO bodbAdminNet 
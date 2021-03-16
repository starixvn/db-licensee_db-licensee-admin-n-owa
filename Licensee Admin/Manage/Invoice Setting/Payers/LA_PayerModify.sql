/*<info serverAlias="DBCUST-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE bodb_licensee
GO

ALTER PROCEDURE [dbo].[LA_PayerModify]
	@PayerID					INT
	, @BrandName				VARCHAR (100)	= ''
	, @CompanyName				NVARCHAR (100)	= ''
	, @Description				NVARCHAR (255)	= ''
	, @AttnName					NVARCHAR (125)	= ''
	, @Address1					NVARCHAR (255)	= ''
	, @Address2					NVARCHAR (255)	= ''
	, @PayerName				VARCHAR (50)
	, @UserID					INT
	, @IsActive					BIT				= 1
	, @IsDeposit				BIT				= 1
	, @LoginIP					VARCHAR (50)	= ''
	, @ErrCode					INT				= 0  OUTPUT
	, @ErrMsg					NVARCHAR(1000)	= '' OUTPUT
	, @InvoiceLanguage 			VARCHAR(7)		= ''
	, @BaseCurrencySettingXml	NVARCHAR(MAX)	= ''
AS
/*
	Created: 20150415@Florent
	Task : Modify Payer infomartion
	DB: DBCUST.bodb_Licensee

	Revisions:
		- 20150918@Victor: Support Chinese on Settings
		- 20161109@bruce.bui: edit non official payer
			1: official payer
			5: non-official payer
		- 20161124@scofield: check unique BrandName
		- 20180318@mason: Add @InvoiceLanguage parameter [#110445]
		- 20190510@Percy: Migrate to DBCUST.bodb_Licensee [RedmineID: #103658]
		- 20190829@Bruce: Adding Licensee Code [#111586]
		- 20210315@Happy: Change BaseCurrency Of Licensee [#151466]
	
	Param's Explannation: 
		@GroupMinFeeSettingData = <Root>
									<BaseCurrencySetting>
										<BaseCurrencyId>6</BaseCurrencyId>
										<LicenseeCode>PHL-LSEE-12BET EUR</LicenseeCode>
										<FromDate>20100101</FromDate>
										<ToDate>20500101</ToDate>
									</BaseCurrencySetting>
									<BaseCurrencySetting>
										<BaseCurrencyId>13</BaseCurrencyId>
										<LicenseeCode>XXX</LicenseeCode>
										<FromDate>20210301</FromDate>
										<ToDate>20500101</ToDate>
									</BaseCurrencySetting>
									<BaseCurrencySetting>
										<BaseCurrencyId>6</BaseCurrencyId>
										<LicenseeCode>PHL-LSEE-12BET EUR</LicenseeCode>
										<FromDate>20210308</FromDate>
										<ToDate>20500101</ToDate>
									</BaseCurrencySetting>
								</Root>'
*/
BEGIN
	SET NOCOUNT ON
	
	-- For writing log
	DECLARE @startRun	DATETIME
		, @endRun		DATETIME
		, @duration		INT
		, @logSPData	NVARCHAR(MAX)
		, @logSPDataOld NVARCHAR(MAX)
		, @xml			XML

	-- Time start
	SET @startRun = GETDATE()

	IF EXISTS (SELECT 1 FROM dbo.OAS_Party p WITH (NOLOCK) WHERE p.PartyID = @PayerID)
	BEGIN
		--write log old
		SET @xml = (
			SELECT	p.PartyId			AS '@pid'
					, p.PartyName		AS '@pn'
					, StatusId			AS '@s'
					, isDeposit			AS '@isd'
					, BrandName			AS '@bn'
					, CompanyName		AS '@cn'
					, pd.AttnName		AS '@an'
					, pd.[Description]	AS '@des'
					, Address1			AS '@a1'
					, Address2			AS '@a2'
					, InvoiceLanguage	AS '@il'
			FROM dbo.OAS_Party p  WITH (NOLOCK)
				INNER JOIN dbo.OAS_PartyDetail pd WITH (NOLOCK) ON p.PartyID = pd.PartyID
			WHERE p.PartyId = @PayerID
			FOR XML PATH('z'), ROOT('r')
		)

		SET @logSPDataOld = REPLACE(CONVERT(NVARCHAR(MAX), @xml), '" />', '"/"')

		UPDATE dbo.OAS_PartyDetail WITH (ROWLOCK, UPDLOCK)
		SET CompanyName = @CompanyName
			, AttnName = @AttnName
			, Description = @Description
			, Address1 = @Address1
			, Address2 = @Address2
			, InvoiceLanguage = @InvoiceLanguage
		WHERE PartyId = @PayerID

		-- only non-official payer can edit payer name, status, deposit status
		IF (SELECT PartyType FROM dbo.OAS_Party WITH(NOLOCK) WHERE PartyID = @PayerID) = 5
		BEGIN
			-- check duplicate name
			IF EXISTS (
				SELECT 1 FROM dbo.OAS_Party WITH(NOLOCK)
				WHERE PartyType IN (1,5) AND PartyID != @PayerID AND PartyName = @PayerName
			) BEGIN
				SELECT @ErrCode = 101,@ErrMsg = 'Payer Name is existed in the system, please try again!'
				RETURN
			END
			
			UPDATE dbo.OAS_Party WITH (ROWLOCK, UPDLOCK)
			SET PartyName = @PayerName
			WHERE PartyId = @PayerID

			UPDATE dbo.OAS_PartyDetail WITH (ROWLOCK, UPDLOCK)
			SET StatusId = @IsActive, IsDeposit = @IsDeposit
			WHERE PartyId = @PayerID
		END
		
		IF EXISTS (
			SELECT 1 FROM dbo.OAS_PartyDetail WITH(NOLOCK)
			WHERE PartyId != @PayerID AND @BrandName != '' AND BrandName = @BrandName
		) BEGIN
			SELECT @ErrCode = 101,@ErrMsg = 'Payer Brand Name is existed in the system, please try again!'
			RETURN
		END
		
		UPDATE dbo.OAS_PartyDetail WITH (ROWLOCK, UPDLOCK)
		SET BrandName = @BrandName
		WHERE PartyId = @PayerID
		
		-- Update base currency settings
		IF ISNULL(@BaseCurrencySettingXml, '') <> ''
		BEGIN
			DECLARE @BaseCurrencySetting TABLE(Idx INT IDENTITY(1, 1)
												, BaseCurrencyId TINYINT
												, LicenseeCode VARCHAR(50)
												, FromDate DATE
												, ToDate DATE)
			DECLARE @docHandler INT
			
			BEGIN TRY
				EXEC sp_xml_preparedocument @docHandler OUTPUT, @BaseCurrencySettingXml
				INSERT INTO @BaseCurrencySetting(BaseCurrencyId, LicenseeCode, FromDate, ToDate)
				SELECT BaseCurrencyId, LicenseeCode, FromDate, ToDate
				FROM OPENXML(@docHandler, 'Root/BaseCurrencySetting')
				WITH(BaseCurrencyId TINYINT 'BaseCurrencyId',
						LicenseeCode VARCHAR(50) 'LicenseeCode',
						FromDate DATE 'FromDate',
						ToDate DATE 'ToDate')
						
				EXEC sp_xml_removedocument @docHandler
			END TRY
			BEGIN CATCH
				SELECT @ErrMsg = 'Base Currency setting data invalid. Please try again.', @ErrCode = 100
				RETURN
			END CATCH
			
			--FromDate must less than ToDate
			IF EXISTS (SELECT TOP 1 1 FROM @BaseCurrencySetting WHERE FromDate > ToDate)
			BEGIN
				SELECT @ErrMsg = 'FromDate could not be later than ToDate', @ErrCode = 506
				RETURN
			END
			
			--Duplicated from date/ to date between settings
			IF EXISTS (
				SELECT TOP 1 1
				FROM @BaseCurrencySetting a 
					LEFT JOIN @BaseCurrencySetting b ON a.Idx <> b.Idx 
				WHERE(a.FromDate <= b.ToDate AND a.ToDate >= B.FromDate))
			BEGIN
				SELECT @ErrMsg = 'Cannot save the setting, please check From date/To date.', @ErrCode = 506
				RETURN
			END
			
			--Region Update Base Currency Settings
			DELETE FROM dbo.OAS_PartyBaseCurrency WITH (ROWLOCK, UPDLOCK) WHERE PartyID = @PayerID

			INSERT INTO dbo.OAS_PartyBaseCurrency(BaseCurrencyId, FromDate, ToDate, LicenseeCode, PartyID)
			SELECT s.BaseCurrencyId, s.FromDate, s.ToDate, s.LicenseeCode, @PayerID
			FROM @BaseCurrencySetting s
			--Endregion
		END

		SET @xml = (
			SELECT	@PayerId			AS '@pid'
					, p.PartyName		AS '@pn'
					, pd.StatusId		AS '@s'
					, pd.IsDeposit		AS '@isd'
					, @BrandName		AS '@bn'
					, @CompanyName		AS '@cn'
					, @AttnName			AS '@an'
					, @Description		AS '@des'
					, @Address1			AS '@a1'
					, @Address2			AS '@a2'
					, @InvoiceLanguage	AS '@il'
			FROM dbo.OAS_Party p WITH (NOLOCK)
				INNER JOIN dbo.OAS_PartyDetail pd WITH (NOLOCK) ON p.PartyID = pd.PartyID
			WHERE p.PartyID = @PayerId
			FOR XML PATH('z'), ROOT('r')
			)
		SET @logSpData = REPLACE(CONVERT(NVARCHAR(MAX), @xml), '" />', '"/"')

		SET @endRun = GETDATE()
		SET @duration = DATEDIFF(MILLISECOND, @startRun, @endRun)

	END
	ELSE
	BEGIN
		SELECT @ErrCode = 101
		,@ErrMsg = 'Cannot save the Payer because it existed in the system, please try again!'
		RETURN
	END

	-- Write Log
	EXEC CustDB.dbo.NAP_SpecialCustSetting_WriteLog_Wrapper
		@UserId			= @UserID
		,@IP			= @LoginIP
		,@LicenseeID	= 0
		,@CurrencyID	= 0
		,@SPName		= 'LA_PayerModify'
		,@CustId		= 0
		,@Duration		= @duration
		,@Data			= @logSPData
		,@OldData		= @logSPDataOld
END
GO
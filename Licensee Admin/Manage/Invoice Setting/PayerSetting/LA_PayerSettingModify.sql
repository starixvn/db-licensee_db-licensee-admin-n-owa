/*<info serverAlias="DBCUST-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE bodb_licensee
GO

ALTER PROCEDURE [dbo].[LA_PayerSettingModify]
	@PayerID				INT	
	, @LaunchDate			DATE = NULL
	, @SuspendedDate		DATE = NULL
	, @TerminatedDate		DATE = NULL
	, @ChargeSettingXML		NVARCHAR (MAX)
	, @MinFeeSettingXML		NVARCHAR (MAX)
	, @WaiveSettingXML		NVARCHAR (MAX)
	, @UserID				INT
	, @LoginIP				VARCHAR (50)	= ''
	, @ErrCode				INT				= 0		OUTPUT
	, @ErrMsg				NVARCHAR(1000)	= ''	OUTPUT	
AS
/*  
	 Created: 2015042$@Florent
	 Task : Add/ Modify Minfee setting
	 DB: DBCUST.bodb_Licensee  
   
	 Revisions:     
		- 20150918@Victor: Support Chinese on Settings
		- 20170220@bruce: update payer settings [#70050]
		- 20180706@bruce: enhance discount group [#94282]
		- 20190510@Percy: Migrate to DBCUST.bodb_Licensee [RedmineID: #103658]
		- 20200831@Mason: Remove redundant code of @PayerGroupId [#138249]
		- 20210318@Mason: Change Base Currency Of Licensee [#151466]
		- 20220118@Percy: Add Licensee Status Setting [RedmineID: #166751]
		- 20220509@Danny: Use String_split built-in function [RemineID: #171831]
		- 20220831@Malcolm: Automate the PT adjustment when the charge rate is changed [RemineID: #171705]

	 Params:				
*/
BEGIN
	SET NOCOUNT ON
	DECLARE @ProductListAll		VARCHAR(100) = ''
			, @MinDate			DATE 
			, @MaxDate			DATE
	
	DECLARE @MinFeeInsertedList VARCHAR(100), @WaiveInsertedList VARCHAR(100)

	-- Update LaunchDate/SuspendedDate/TerminatedDate
	DECLARE @Old_LaunchDate DATE, @Old_SuspendedDate DATE, @Old_TerminatedDate DATE
	SELECT  @Old_LaunchDate = LaunchDate, @Old_SuspendedDate = SuspendedDate, @Old_TerminatedDate = TerminatedDate
	FROM dbo.OAS_PartyDetail WITH (NOLOCK)
	WHERE PartyId = @PayerId

	BEGIN TRY
		UPDATE dbo.OAS_PartyDetail WITH (ROWLOCK)
		SET LaunchDate = @LaunchDate, SuspendedDate = @SuspendedDate, TerminatedDate = @TerminatedDate
		WHERE PartyId = @PayerId
	END TRY
	BEGIN CATCH
		SELECT @ErrCode = 101, @ErrMsg = 'Update failed. Please try again.'
		RETURN
	END CATCH

	--Minfee
	EXEC dbo.LA_MinFeeSettingModify
		@PayerID				= @PayerID
		, @MinFeeSettingXML		= @MinFeeSettingXML
		, @UserID				= @UserID
		, @LoginIP				= @LoginIP
		, @ErrCode				= @ErrCode		OUTPUT
		, @ErrMsg				= @ErrMsg		OUTPUT
		, @MinfeeInsertedList	= @MinFeeInsertedList  OUTPUT
	IF @ErrCode <> 0 
		BEGIN
			RETURN
		END
	--Waive
	EXEC dbo.LA_MinFeeSettingModify
		@PayerID				= @PayerID
		, @MinFeeSettingXML		= @WaiveSettingXML
		, @UserID				= @UserID
		, @LoginIP				= @LoginIP
		, @ErrCode				= @ErrCode		OUTPUT
		, @ErrMsg				= @ErrMsg		OUTPUT
		, @MinfeeInsertedList	= @WaiveInsertedList OUTPUT
	IF @ErrCode <> 0 
		BEGIN
			--Rollback LaunchDate/SuspendedDate/TerminatedDate
			UPDATE dbo.OAS_PartyDetail WITH (ROWLOCK)
			SET LaunchDate = @Old_LaunchDate, SuspendedDate = @Old_SuspendedDate, TerminatedDate = @Old_TerminatedDate
			WHERE PartyId = @PayerId

			--Rollback Minfee
			IF ISNULL(@MinFeeInsertedList, 0) <> 0
				DELETE dbo.LA_MinFee WITH (ROWLOCK, UPDLOCK) WHERE PartyId = @PayerID AND MinFeeId IN (SELECT value FROM STRING_SPLIT(@MinFeeInsertedList, ','))
			RETURN
		END
	--Modify Chargerate Setting
	EXEC dbo.LA_ChargeRateSettingModify
		@PayerID				= @PayerID
		, @ChargeSettingXML		= @ChargeSettingXML
		, @UserID				= @UserID
		, @LoginIP				= @LoginIP
		, @ErrCode				= @ErrCode		OUTPUT
		, @ErrMsg				= @ErrMsg		OUTPUT			

	IF @ErrCode <> 0 
		BEGIN
			--Rollback LaunchDate/SuspendedDate/TerminatedDate
			UPDATE dbo.OAS_PartyDetail WITH (ROWLOCK)
			SET LaunchDate = @Old_LaunchDate, SuspendedDate = @Old_SuspendedDate, TerminatedDate = @Old_TerminatedDate
			WHERE PartyId = @PayerId

			--Rollback Minfee
			IF ISNULL(@MinFeeInsertedList, 0) <> 0
				DELETE dbo.LA_MinFee WITH (ROWLOCK, UPDLOCK) WHERE PartyId = @PayerID AND MinFeeId IN (SELECT value FROM STRING_SPLIT(@MinFeeInsertedList, ','))
			--Rollback waive
			IF ISNULL(@WaiveInsertedList, 0 ) <> 0
				DELETE dbo.LA_MinFee WITH (ROWLOCK, UPDLOCK) WHERE PartyId = @PayerID AND MinFeeId IN (SELECT value FROM STRING_SPLIT(@WaiveInsertedList, ','))
			RETURN
		END

	DECLARE @SiteName VARCHAR(20) ='', @InputPT VARCHAR(MAX), @ChargeRateXML XML

	SELECT @ChargeRateXML = CONVERT(XML, @ChargeSettingXML)
	
	DECLARE @ChargeRate TABLE (ProductId INT, Rate DECIMAL(19,4))

	SELECT @SiteName = l.LicenseeName
	FROM dbo.OAS_Party p WITH(NOLOCK)
		INNER JOIN dbo.Licensees l WITH(NOLOCK) ON p.OldRefID = l.LicenseeID
	WHERE l.IsDeposit = 1 AND p.PartyID = @PayerID

	INSERT INTO @ChargeRate (ProductId, Rate)
	SELECT
		t.c.value('(ProductId/text())[1]', 'INT') AS ProductId,	
		t.c.value('(Rate/text())[1]', 'DECIMAL(19,4)') AS Rate
	FROM @ChargeRateXML.nodes('ChargeSettings/ChargeSetting') AS t(c)
	OPTION (OPTIMIZE FOR (@ChargeRateXML = NULL))

	UPDATE c
		SET c.ProductId = CASE WHEN c.ProductId = 0 THEN 1 ELSE p.ProductId END
	FROM @ChargeRate c
		LEFT JOIN dbo.Product3rd pr WITH(NOLOCK) ON pr.Productid = c.ProductId
		LEFT JOIN DBPRO.bodb02.dbo.Products p WITH (NOLOCK) ON p.ProductPrefix = pr.ProductPrefix

	SELECT @InputPT = CONVERT(VARCHAR(MAX), 
	(
		SELECT ProductId AS '@PID', 0 AS '@CID',1 - Rate AS '@PT' 
		FROM @ChargeRate FOR XML PATH ('PT'), ROOT('ROOT')
	))

	EXEC CustDB.dbo.Acc_Dep_LicenseeSetting_PTSettingUpd
		@Site = @SiteName
		,@InputPT = @InputPT
		,@UserID = @UserID
		,@IP = @LoginIP
		,@ErrCode = @ErrCode OUTPUT
		,@ErrMsg = @ErrMsg OUTPUT	

	IF @ErrCode  <> 0
	BEGIN
		RETURN
	END

END
GO
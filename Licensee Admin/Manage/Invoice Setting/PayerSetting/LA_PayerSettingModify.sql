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
				DELETE dbo.LA_MinFee WITH (ROWLOCK, UPDLOCK) WHERE PartyId = @PayerID AND MinFeeId IN (SELECT val FROM dbo.strSplit(@MinFeeInsertedList, ','))
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
				DELETE dbo.LA_MinFee WITH (ROWLOCK, UPDLOCK) WHERE PartyId = @PayerID AND MinFeeId IN (SELECT val FROM dbo.strSplit(@MinFeeInsertedList, ','))
			--Rollback waive
			IF ISNULL(@WaiveInsertedList, 0 ) <> 0
				DELETE dbo.LA_MinFee WITH (ROWLOCK, UPDLOCK) WHERE PartyId = @PayerID AND MinFeeId IN (SELECT val FROM dbo.strSplit(@WaiveInsertedList, ','))
			RETURN
		END
END
GO
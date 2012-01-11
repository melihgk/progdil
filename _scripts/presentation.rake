# Encoding: utf-8
# ------------------------------------------------------------------------------
# Landslide Sunumları için Görevler
# ------------------------------------------------------------------------------

require 'pathname'
require 'pythonconfig'
require 'yaml'

# Site yapılandırmasında sunumlara ait bölümü al
CONFIG = Config.fetch('presentation', {})

#***********************
# presentation:
#             directory:
#             conffile:

# Sunum dizini
PRESENTATION_DIR = CONFIG.fetch('directory', 'p')
# Öntanımlı landslide yapılandırması
DEFAULT_CONFFILE = CONFIG.fetch('conffile', '_templates/presentation.cfg') #~~~~~~~ 1.si varsa 1.yi al yoksa 2.yi al
# Sunum indeksi
INDEX_FILE = File.join(PRESENTATION_DIR, 'index.html') #~~~~~~~ "/" ile birleştiriyor
# İzin verilen en büyük resim boyutları
IMAGE_GEOMETRY = [ 733, 550 ]
# Bağımlılıklar için yapılandırmada hangi anahtarlara bakılacak
DEPEND_KEYS    = %w(source css js) #~~~~~~~ liste ["source", "css", "js"]
# Vara daima bağımlılık verilecek dosya/dizinler
DEPEND_ALWAYS  = %w(media)
# Hedef Görevler ve tanımları
TASKS = { #~~~~~~~ HASH yapısı
    :index   => 'sunumları indeksle',
    :build   => 'sunumları oluştur',
    :clean   => 'sunumları temizle',
    :view    => 'sunumları görüntüle',
    :run     => 'sunumları sun',
    :optim   => 'resimleri iyileştir',
    :default => 'öntanımlı görev',
}

# Sunum bilgileri
presentation   = {}
# Etiket bilgileri
tag            = {}

class File
  @@absolute_path_here = Pathname.new(Pathname.pwd)
  def self.to_herepath(path)
    Pathname.new(File.expand_path(path)).relative_path_from(@@absolute_path_here).to_s
  end
  def self.to_filelist(path)
    File.directory?(path) ?
      FileList[File.join(path, '*')].select { |f| File.file?(f) } :
      [path]
  end
end

def png_comment(file, string)
  require 'chunky_png'
  require 'oily_png'

  image = ChunkyPNG::Image.from_file(file)
  image.metadata['Comment'] = 'raked'
  image.save(file)
end

def png_optim(file, threshold=40000)
  #~~~~~~~~~~~~ belli bir eşik değerine göre resmi optime et.
  return if File.new(file).size < threshold
  sh "pngnq -f -e .png-nq #{file}"
  out = "#{file}-nq"
  if File.exist?(out)
    $?.success? ? File.rename(out, file) : File.delete(out)
  end
  # İşlendiğini belirtmek için not düş.
  png_comment(file, 'raked')
end

def jpg_optim(file)
  sh "jpegoptim -q -m80 #{file}"
  sh "mogrify -comment 'raked' #{file}"
end

def optim
  pngs, jpgs = FileList["**/*.png"], FileList["**/*.jpg", "**/*.jpeg"]

  # Optimize edilmişleri çıkar.
  [pngs, jpgs].each do |a|
    a.reject! { |f| %x{identify -format '%c' #{f}} =~ /[Rr]aked/ }
  end

  # Resim boyutlarını ayarla.
  (pngs + jpgs).each do |f|
    w, h = %x{identify -format '%[fx:w] %[fx:h]' #{f}}.split.map { |e| e.to_i }
    size, i = [w, h].each_with_index.max
    if size > IMAGE_GEOMETRY[i]
      arg = (i > 0 ? 'x' : '') + IMAGE_GEOMETRY[i].to_s
      sh "mogrify -resize #{arg} #{f}"
    end
  end

  pngs.each { |f| png_optim(f) }
  jpgs.each { |f| jpg_optim(f) }


  #~~~~~~~ Resimleri tekrardan üretmeye çalışıyoruz.
  (pngs + jpgs).each do |f|
    name = File.basename f
    FileList["*/*.md"].each do |src|
      sh "grep -q '(.*#{name})' #{src} && touch #{src}"
    end
  end
end

default_conffile = File.expand_path(DEFAULT_CONFFILE) #~~~~~~~ DEFAULT_CONFFILE'in tam yolunu alıyoruz.

# Sunum bilgilerini üret
FileList[File.join(PRESENTATION_DIR, "[^_.]*")].each do |dir| #~~~~~~~ Dir['*'] "_" ile başlamayan tüm dizinleri getir
  next unless File.directory?(dir) #~~~~~~~ dizin yoksa devam et pass geç
  chdir dir do #~~~~~~~ dizine gir
    name = File.basename(dir) #~~~~~~~ alt kısmını al yani /home/foo/bar => bar alıyor
    conffile = File.exists?('presentation.cfg') ? 'presentation.cfg' : default_conffile
    #~~~~~~~ presentation.cfg var ise onu al yoksa default_conffile'i al
    config = File.open(conffile, "r") do |f| #~~~~~~~ ='e göre parçalayıp hash dönen bir işlem
      PythonConfig::ConfigParser.new(f)
    end

    landslide = config['landslide']
    if ! landslide #~~~~~~~ yoksa hata ver
      $stderr.puts "#{dir}: 'landslide' bölümü tanımlanmamış"
      exit 1
    end

    if landslide['destination'] #~~~~~~~ presentation.cfg içindeki key de, destination diye birşey var ise hata ver çık
      $stderr.puts "#{dir}: 'destination' ayarı kullanılmış; hedef dosya belirtilmeyin"
      exit 1
    end

    if File.exists?('index.md') #~~~~~~~ index.md yok ise
      base = 'index'
      ispublic = true #~~~~~~~ genel bir tek şablon sunum/slayt vardır
    elsif File.exists?('presentation.md') # presentation.mf yok ise
      base = 'presentation'
      ispublic = false #~~~~~~~ çoklu bir şablon vardır
    else
      $stderr.puts "#{dir}: sunum kaynağı 'presentation.md' veya 'index.md' olmalı"
      exit 1
    end
    #~~~~~~~ sunumun html'ini ve resmi için ayarlayan
    basename = base + '.html'
    thumbnail = File.to_herepath(base + '.png') #~~~~~~~ resmin tam yolu
    target = File.to_herepath(basename) #~~~~~~~ html sayfanın(sunum/şablon) tam yolu

    # bağımlılık verilecek tüm dosyaları listele
    deps = []
    (DEPEND_ALWAYS + landslide.values_at(*DEPEND_KEYS)).compact.each do |v| #~~~~~~~~~ css dizini al, onun altındakileri de al
      deps += v.split.select { |p| File.exists?(p) }.map { |p| File.to_filelist(p) }.flatten
      #~~~~~~~ css/x.css css/y.css ise => css + y.css + css
    end
    #~~~~~~~~ deps = ["css", "x.css", "y.css"]
    # bağımlılık ağacının çalışması için tüm yolları bu dizine göreceli yap
    deps.map! { |e| File.to_herepath(e) } # bu dizindeki pathleri al
    deps.delete(target) #~~~~~~~ html sayfasını deps'ten sil
    deps.delete(thumbnail) #~~~~~~~ png dosyasını da deps'ten sil

    # TODO etiketleri işle
    tags = []

   presentation[dir] = { #~~~ global presentation = {} böyleydi. İçini doldurduk.
      :basename  => basename,	# üreteceğimiz sunum dosyasının baz adı
      :conffile  => conffile,	# landslide konfigürasyonu (mutlak dosya yolu)
      :deps      => deps,	# sunum bağımlılıkları                      #~~~~~ css vs...
      :directory => dir,	# sunum dizini (tepe dizine göreli)
      :name      => name,	# sunum ismi
      :public    => ispublic,	# sunum dışarı açık mı
      :tags      => tags,	# sunum etiketleri
      :target    => target,	# üreteceğimiz sunum dosyası (tepe dizine göreli) #~~~~ html
      :thumbnail => thumbnail, 	# sunum için küçük resim                          #~~~~ png
    }
  end
end

# TODO etiket bilgilerini üret
presentation.each do |k, v| #~~~~~~~~~~~~ tag'leri üretmeye çalışıyor
  v[:tags].each do |t|
    tag[t] ||= []
    tag[t] << k
  end
end

# Görev tablosunu hazırla
tasktab = Hash[*TASKS.map { |k, v| [k, { :desc => v, :tasks => [] }] }.flatten]

# Görevleri üret
presentation.each do |presentation, data|
  # her alt sunum dizini için bir alt görev tanımlıyoruz
  ns = namespace presentation do
    # sunum dosyaları
    file data[:target] => data[:deps] do |t|
      chdir presentation do
        sh "landslide -i #{data[:conffile]}" #~~~~ konsoldan lanslide ile conffile
        # XXX: Slayt bağlamı iOS tarayıcılarında sorun çıkarıyor.  Kirli bir çözüm!
        #~~~~~~~~ presentation.html'de
        # ([[:blank:]]*var hiddenContext = \)false\(;[[:blank:]]*$\) geçenleri
        # \1true\2 yap
        sh 'sed -i -e "s/^\([[:blank:]]*var hiddenContext = \)false\(;[[:blank:]]*$\)/\1true\2/" presentation.html'


        unless data[:basename] == 'presentation.html'
          mv 'presentation.html', data[:basename]
	  #~~~~~~~~ data[:basename] presentation.html değilse
          #~~~~~~~~ presentation.html 'i data[:basename] olarak ismini değiştir
        end
      end
    end

    # küçük resimler
    #~~~~~~~~~~ png resim ile ilgili bir göreve bakıyor
    file data[:thumbnail] => data[:target] do 
      next unless data[:public] #~~~~~~~~~~ data[:public] yok ise devam et
      sh "cutycapt " +          #~~~~~~~~~~ ile konsoldan kod çalıştır
          "--url=file://#{File.absolute_path(data[:target])}#slide1 " +
          "--out=#{data[:thumbnail]} " +
          "--user-style-string='div.slides { width: 900px; overflow: hidden; }' " +
          "--min-width=1024 " +
          "--min-height=768 " +
          "--delay=1000"
      sh "mogrify -resize 240 #{data[:thumbnail]}"
      #~~~~~~~~~ genişlik ve yüksekliğini 240 olarak ata
      
      png_optim(data[:thumbnail])
    end

    task :optim do 
    #~~~~~~~~~~ $ rake optim :  deyince presentation dizinine girip resimleri optim fonksiyonu ile optime eder.
      chdir presentation do
        optim
      end
    end

    task :index => data[:thumbnail] 
    #~~~~~~ $ rake index : deyince sunumun png'sine bağımlı olarak data[:thumbnail] görevini çalıştırır.
   
    #~~~~~~ sayfa için önce resim gerekli
    task :build => [:optim, data[:target], :index]
                #~~~~~~~~~~ $ rake build : deyince optim,
                #~~~~~~~~~~ data[:target](html), index çalışması gerektir bağımlıdır.
                #~~~~~~~~~~ YANI RESİMLERİ OPTİME ET; GÖREVLERİ
                #~~~~~~~~~~ ÇALIŞTIR; ANASAYFA İLE İLGİLİ GÖREVİ ÇALIŞTIR

    task :view do  #~~~~~~~~~~~~~~~ $ rake view
      if File.exists?(data[:target]) #~~~~~~~~~~~~~ görevler dizini yok ise onu oluştur
        sh "touch #{data[:directory]}; #{browse_command data[:target]}"
      else
        $stderr.puts "#{data[:target]} bulunamadı; önce inşa edin"
      end
    end

    task :run => [:build, :view] #~~~~~~~~ $ rake run
                                 # Görev build, view çalışmalıdır.

    task :clean do #~~~~~~~~~~ $ rake clean
      rm_f data[:target]       #~~~~~~~ data[:target] dizini sil / html'i siliyoruz.
      rm_f data[:thumbnail]    #~~~~~~~~~ data[:thumbnail] dizini sil / png'yi siliyoruz.
    end

    task :default => :build #~~~~~~~ $rake default:
                            # build görevine bağlıdır.
  end

  # alt görevleri görev tablosuna işle
  ns.tasks.map(&:to_s).each do |t|
    _, _, name = t.partition(":").map(&:to_sym)
    next unless tasktab[name]
    tasktab[name][:tasks] << t
  end
end

namespace :p do
  # görev tablosundan yararlanarak üst isim uzayında ilgili görevleri tanımla
  tasktab.each do |name, info|
    desc info[:desc] #~~~~~~~~~~~~ desc fonskyionu ile kullanıcıya bilgi göster
    task name => info[:tasks]
    task name[0] => name
  end

  task :build do #~~~~~~ GENEL olrak INDEX_FILE ismindeki dosyaya JEYKLL ismini oluştuuryor.
                # ör:
                # index
                # ---

    index = YAML.load_file(INDEX_FILE) || {} #~~~~~~~ INDEX_FILE var ise onu al yoksa {} bunu al
    presentations = presentation.values.select { |v| v[:public] }.map { |v| v[:directory] }.sort
    unless index and presentations == index['presentations']
      index['presentations'] = presentations
      File.open(INDEX_FILE, 'w') do |f|
        f.write(index.to_yaml)
        f.write("---\n")
      end
    end
  end

  desc "sunum menüsü"
  task :menu do #~~~~~~~~~~ sunum menüsü oluşturup sunumu seçer sunumun RUN eder yani gösterir.
    lookup = Hash[
      *presentation.sort_by do |k, v|
        File.mtime(v[:directory])
      end
      .reverse
      .map { |k, v| [v[:name], k] }
      .flatten
    ]
    name = choose do |menu|
      menu.default = "1" #~~~~~~~~~~~~ sunumlardan default olarak 1. sunumu ilk sunumu seçmemizi ister
      menu.prompt = color(
        'Lütfen sunum seçin ', :headline
      ) + '[' + color("#{menu.default}", :special) + ']'
      menu.choices(*lookup.keys)
    end
    directory = lookup[name]
    Rake::Task["#{directory}:run"].invoke
  end
  task :m => :menu #~~~~~~~~ $  rake menu yerine rake m de denilebilir
end

desc "sunum menüsü"
task :p => ["p:menu"] #~~~~~~~ $rake p deyince $ rake p:menu çalışır, menü gelir ve sunumu açarız
task :presentation => :p


# rake build derleme yapıyor.
# rake p deyince de sunumları gösteriyor.
